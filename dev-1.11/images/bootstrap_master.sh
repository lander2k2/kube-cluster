#!/bin/bash

PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')
PEER_NAME=$(hostname)
API_LB_EP=0
ETCD_TLS=0
ETCD0_IP=0
ETCD1_IP=0
ETCD2_IP=0
INIT_CLUSTER=0
K8S_TLS=0

echo "${PEER_NAME}=https://${PRIVATE_IP}:2380" > /tmp/etcd_member
echo "${PRIVATE_IP}" > /tmp/private_ip

sudo mkdir -p /etc/kubernetes/pki/etcd

while [ $ETCD_TLS -eq 0 ]; do
    if [ -f /tmp/etcd_tls.tar.gz ]; then
        (cd /tmp; tar xvf /tmp/etcd_tls.tar.gz)
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca-key.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/client.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/client-key.pem /etc/kubernetes/pki/etcd/
        sudo mv /tmp/etc/kubernetes/pki/etcd/ca-config.json /etc/kubernetes/pki/etcd/
        ETCD_TLS=1
    else
        echo "etcd tls assets not yet available"
        sleep 10
    fi
done

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

sudo tee /etc/etcd.env << END
PEER_NAME=$PEER_NAME
PRIVATE_IP=$PRIVATE_IP
END

while [ $INIT_CLUSTER -eq 0 ]; do
    if [ -f /tmp/init_cluster ]; then
        INIT_CLUSTER=$(cat /tmp/init_cluster)
    else
        echo "initial cluster values not yet available"
        sleep 10
    fi
done

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
    --initial-cluster ${INIT_CLUSTER} \
    --initial-cluster-token my-etcd-token \
    --initial-cluster-state new

[Install]
WantedBy=multi-user.target
END

sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

while [ $API_LB_EP -eq 0 ]; do
    if [ -f /tmp/api_lb_ep ]; then
        API_LB_EP=$(cat /tmp/api_lb_ep)
    else
        echo "API load balancer endpoint not yet available"
        sleep 10
    fi
done

while [ $ETCD0_IP -eq 0 ]; do
    if [ -f /tmp/etcd0_ip ]; then
        ETCD0_IP=$(cat /tmp/etcd0_ip)
    else
        echo "etcd0 IP not yet available"
        sleep 10
    fi
done

while [ $ETCD1_IP -eq 0 ]; do
    if [ -f /tmp/etcd1_ip ]; then
        ETCD1_IP=$(cat /tmp/etcd1_ip)
    else
        echo "etcd1 IP not yet available"
        sleep 10
    fi
done

while [ $ETCD2_IP -eq 0 ]; do
    if [ -f /tmp/etcd2_ip ]; then
        ETCD2_IP=$(cat /tmp/etcd2_ip)
    else
        echo "etcd2 IP not yet available"
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
  - https://${ETCD0_IP}:2379
  - https://${ETCD1_IP}:2379
  - https://${ETCD2_IP}:2379
  caFile: /etc/kubernetes/pki/etcd/ca.pem
  certFile: /etc/kubernetes/pki/etcd/client.pem
  keyFile: /etc/kubernetes/pki/etcd/client-key.pem
networking:
  podSubnet: 192.168.0.0/16
apiServerCertSANs:
- ${API_LB_EP}
apiServerExtraArgs:
  endpoint-reconciler-type: "lease"
EOF

while [ $K8S_TLS -eq 0 ]; do
    if [ -f /tmp/k8s_tls.tar.gz ]; then
        (cd /tmp; tar xvf /tmp/k8s_tls.tar.gz)
        sudo mv /tmp/etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/
        sudo mv /tmp/etc/kubernetes/pki/ca.key /etc/kubernetes/pki/
        sudo mv /tmp/etc/kubernetes/pki/sa.key /etc/kubernetes/pki/
        sudo mv /tmp/etc/kubernetes/pki/sa.pub /etc/kubernetes/pki/
        K8S_TLS=1
    else
        echo "k8s TLS assets not yet available"
        sleep 10
    fi
done

sudo kubeadm init --config=/tmp/kubeadm-config.yaml

