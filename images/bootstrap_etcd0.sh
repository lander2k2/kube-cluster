#!/bin/bash

# wait for permanent hostname
HOSTNAME_PRE="ip-172"
while [ "$HOSTNAME_PRE" != "ip-10" ]; do
    echo "permanent hostname not yet available"
    sleep 10
    HOSTNAME_PRE=$(hostname | cut -c1-5)
done

# shut up broken DNS warnings
ipaddr=`ifconfig eth0 | awk 'match($0,/inet addr:([^ ]+)/,m) {print m[1]}'`
host=`hostname`

if ! grep -q $host /etc/hosts; then
  echo "fixing broken /etc/hosts"
  cat <<EOF | sudo dd oflag=append conv=notrunc of=/etc/hosts >/dev/null 2>&1
# added by bootstrap_etcd0.sh `date`
$ipaddr $host
EOF
fi

PRIVATE_IP=""
while [ "$PRIVATE_IP" == "" ]; do
    echo "private IP not yet available"
    sleep 10
    PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')
done

PEER_NAME=$(hostname)
INIT_CLUSTER=0

echo "${PEER_NAME}=https://${PRIVATE_IP}:2380" > /tmp/etcd_member
echo "${PRIVATE_IP}" > /tmp/private_ip

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
#sudo chown ubuntu:ubuntu /tmp/etcd_tls.tar.gz

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

# clean
sudo rm /tmp/etcd_member \
    /tmp/etcd_tls.tar.gz \
    /tmp/init_cluster \
    /tmp/private_ip

