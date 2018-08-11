#!/bin/bash

PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')
PEER_NAME=$(hostname)
API_LB_EP=0

#echo "${PEER_NAME}=https://${PRIVATE_IP}:2380" > /tmp/etcd_member
echo "${PRIVATE_IP}" > /tmp/private_ip

################################################################################
# etcd
################################################################################

sudo mkdir -p /etc/kubernetes/pki/etcd
sudo cat > /etc/kubernetes/pki/etcd/ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF

sudo cat > /etc/kubernetes/pki/etcd/ca-csr.json <<EOF
{
    "CN": "etcd",
    "key": {
        "algo": "rsa",
        "size": 2048
    }
}
EOF

(cd /etc/kubernetes/pki/etcd; sudo cfssl gencert -initca /etc/kubernetes/pki/etcd/ca-csr.json | sudo cfssljson -bare ca -)

sudo cat > /etc/kubernetes/pki/etcd/client.json <<EOF
{
    "CN": "client",
    "key": {
        "algo": "ecdsa",
        "size": 256
    }
}
EOF

(cd /etc/kubernetes/pki/etcd; sudo cfssl gencert \
    -ca=/etc/kubernetes/pki/etcd/ca.pem \
    -ca-key=/etc/kubernetes/pki/etcd/ca-key.pem \
    -config=/etc/kubernetes/pki/etcd/ca-config.json \
    -profile=client \
    /etc/kubernetes/pki/etcd/client.json | cfssljson -bare client)

cfssl print-defaults csr | sudo tee /etc/kubernetes/pki/etcd/config.json
sudo sed -i '0,/CN/{s/example\.net/'"$PEER_NAME"'/}' /etc/kubernetes/pki/etcd/config.json
sudo sed -i 's/www\.example\.net/'"$PRIVATE_IP"'/' /etc/kubernetes/pki/etcd/config.json
sudo sed -i 's/example\.net/'"$PEER_NAME"'/' /etc/kubernetes/pki/etcd/config.json

(cd /etc/kubernetes/pki/etcd; sudo cfssl gencert \
    -ca=/etc/kubernetes/pki/etcd/ca.pem \
    -ca-key=/etc/kubernetes/pki/etcd/ca-key.pem \
    -config=/etc/kubernetes/pki/etcd/ca-config.json \
    -profile=server \
    /etc/kubernetes/pki/etcd/config.json | cfssljson -bare server)

(cd /etc/kubernetes/pki/etcd; sudo cfssl gencert \
    -ca=/etc/kubernetes/pki/etcd/ca.pem \
    -ca-key=/etc/kubernetes/pki/etcd/ca-key.pem \
    -config=/etc/kubernetes/pki/etcd/ca-config.json \
    -profile=peer \
    /etc/kubernetes/pki/etcd/config.json | cfssljson -bare peer)

sudo tar cvf /tmp/etcd_tls.tar.gz /etc/kubernetes/pki/etcd
sudo chown ubuntu:ubuntu /tmp/etcd_tls.tar.gz

sudo tee /etc/etcd.env << END
PEER_NAME=$PEER_NAME
PRIVATE_IP=$PRIVATE_IP
END

sudo tee /etc/systemd/system/etcd.service << END
[Unit]
Description=etcd
Documentation=https://github.com/coreos/etcd
Conflicts=etcd.service
Conflicts=etcd2.service

[Service]
EnvironmentFile=/etc/etcd.env
Type=notify
Restart=always
RestartSec=5s
LimitNOFILE=40000
TimeoutStartSec=0

ExecStart=/usr/local/bin/etcd --name ${PEER_NAME} \
    --data-dir /var/lib/etcd \
    --listen-client-urls https://${PRIVATE_IP}:2379 \
    --advertise-client-urls https://${PRIVATE_IP}:2379 \
    --listen-peer-urls https://${PRIVATE_IP}:2380 \
    --initial-advertise-peer-urls https://${PRIVATE_IP}:2380 \
    --cert-file=/etc/kubernetes/pki/etcd/server.pem \
    --key-file=/etc/kubernetes/pki/etcd/server-key.pem \
    --client-cert-auth \
    --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem \
    --peer-cert-file=/etc/kubernetes/pki/etcd/peer.pem \
    --peer-key-file=/etc/kubernetes/pki/etcd/peer-key.pem \
    --peer-client-cert-auth \
    --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.pem \
    --initial-cluster "${PEER_NAME}=https://${PRIVATE_IP}:2380" \
    --initial-cluster-token my-etcd-token \
    --initial-cluster-state new

[Install]
WantedBy=multi-user.target
END

sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

################################################################################
# cluster-api
################################################################################
kubeadm alpha phase certs front-proxy-ca

mkdir -p /etc/kubernetes/pki/cluster-api
cat << EOF > /etc/kubernetes/pki/cluster-api/cluster-api.json
{
    "hosts": [
        "cluster-api.svc.cluster.local",
        "cluster-api.svc"
    ],
    "cn": "cluster-api.cluster-api.svc",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C":  "US",
            "L":  "Seattle",
            "O":  "Heptio, Inc.",
            "OU": "Dev",
            "ST": "Washington"
        }
    ]
}
EOF

cd /etc/kubernetes/pki/cluster-api
cfssl genkey cluster-api.json | cfssljson -bare cluster-api
cfssl sign -ca /etc/kubernetes/pki/front-proxy-ca.crt -ca-key /etc/kubernetes/pki/front-proxy-ca.key -csr cluster-api.csr | cfssljson -bare cluster-api
cd -

################################################################################
# kubernetes
################################################################################

while [ $API_LB_EP -eq 0 ]; do
    if [ -f /tmp/api_lb_ep ]; then
        API_LB_EP=$(cat /tmp/api_lb_ep)
    else
        echo "API load balancer endpoint not yet available"
        sleep 10
    fi
done

cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: ${PRIVATE_IP}
etcd:
  endpoints:
  - https://${PRIVATE_IP}:2379
  caFile: /etc/kubernetes/pki/etcd/ca.pem
  certFile: /etc/kubernetes/pki/etcd/client.pem
  keyFile: /etc/kubernetes/pki/etcd/client-key.pem
networking:
  podSubnet: 192.168.0.0/16
apiServerCertSANs:
- ${API_LB_EP}
apiServerExtraArgs:
  "endpoint-reconciler-type": "lease"
  "requestheader-client-ca-file": "/etc/kubernetes/pki/front-proxy-ca.crt"
  "proxy-client-cert-file": "/etc/kubernetes/pki/cluster-api/cluster-api.pem"
  "proxy-client-key-file": "/etc/kubernetes/pki/cluster-api/cluster-api-key.pem"
  "requestheader-allowed-names": "cluster-api.cluster-api.svc"
  "requestheader-extra-headers-prefix": "X-Remote-Extra-"
  "requestheader-group-headers": "X-Remote-Group"
  "requestheader-username-headers": "X-Remote-User"
  "enable-aggregator-routing": "true"
kubernetesVersion: "1.9.7"
EOF

sudo kubeadm init --config=/tmp/kubeadm-config.yaml

sudo tar cvf /tmp/k8s_tls.tar.gz /etc/kubernetes/pki

mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico-rbac-kdd.yaml
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico.yaml

kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/master-
kubectl --kubeconfig /etc/kubernetes/admin.conf create namespace cluster-api
kubectl --kubeconfig /etc/kubernetes/admin.conf -n cluster-api create secret generic cluster-api-pki --from-file=cert=/etc/kubernetes/pki/cluster-api/cluster-api.pem --from-file=key=/etc/kubernetes/pki/cluster-api/cluster-api-key.pem

sudo kubeadm token create --description "Token created and used by kube-cluster bootstrapper" --print-join-command > /tmp/join
sudo chown ubuntu:ubuntu /tmp/join

