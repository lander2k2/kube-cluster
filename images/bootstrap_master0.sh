#!/bin/bash

PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')
API_LB_EP=0
ETCD_TLS=0
ETCD0_IP=0
ETCD1_IP=0
ETCD2_IP=0
PROXY_EP=0
IMAGE_REPO=0

# proxy vars for docker
while [ $PROXY_EP -eq 0 ]; do
    if [ -f /tmp/proxy_ep ]; then
        PROXY_EP=$(cat /tmp/proxy_ep)
    else
        echo "proxy endpoint not yet available"
        sleep 10
    fi
done

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$PROXY_EP:3128/" "HTTPS_PROXY=http://$PROXY_EP:3128/"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# get etcd TLS assets so API server can connect
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

# get the ELB domain name for the API server
while [ $API_LB_EP -eq 0 ]; do
    if [ -f /tmp/api_lb_ep ]; then
        API_LB_EP=$(cat /tmp/api_lb_ep)
    else
        echo "API load balancer endpoint not yet available"
        sleep 10
    fi
done

# get the IPs for the etcd members
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

# image repo to pull images from
while [ $IMAGE_REPO -eq 0 ]; do
    if [ -f /tmp/image_repo ]; then
        IMAGE_REPO=$(cat /tmp/image_repo)
    else
        echo "image repo not yet available"
        sleep 10
    fi
done

# generate kubeadm config
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
kubernetesVersion: "stable-1.9"
imageRepository: $IMAGE_REPO
EOF

# initialize
HTTP_PROXY=http://$PROXY_EP:3128 \
    http_proxy=http://$PROXY_EP:3128 \
    HTTPS_PROXY=http://$PROXY_EP:3128 \
    https_proxy=http://$PROXY_EP:3128 \
    NO_PROXY=10.0.0.0/16,192.168.0.0/16 \
    no_proxy=10.0.0.0/16,192.168.0.0/16 \
    sudo -E bash -c 'kubeadm init --config=/tmp/kubeadm-config.yaml'

# tar up the K8s TLS assets to distribute to other masters
sudo tar cvf /tmp/k8s_tls.tar.gz /etc/kubernetes/pki

# put the kubeconfig in a convenient location
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube

# deploy networking
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico-rbac-kdd.yaml
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f /etc/k8s_bootstrap/calico.yaml

# get a join command ready for distribution to workers
sudo kubeadm token create --description "Token created and used by kube-cluster bootstrapper" --print-join-command > /tmp/join
sudo chown ubuntu:ubuntu /tmp/join

