#!/bin/bash

# wait for permanent hostname
HOSTNAME_PRE="ip-172"
while [ "$HOSTNAME_PRE" != "ip-10" ]; do
    echo "permanent hostname not yet available"
    sleep 10
    HOSTNAME_PRE=$(hostname | cut -c1-5)
done
HOSTNAME=$(hostname)

PRIVATE_IP=""
while [ "$PRIVATE_IP" == "" ]; do
    echo "private IP not yet available"
    sleep 10
    PRIVATE_IP=$(ip addr show ens3 | grep -Po 'inet \K[\d.]+')
done

# shut up broken DNS warnings
if ! grep -q $host /etc/hosts; then
  echo "fixing broken /etc/hosts"
  cat <<EOF | sudo dd oflag=append conv=notrunc of=/etc/hosts >/dev/null 2>&1
# added by bootstrap_etcd0.sh `date`
$PRIVATE_IP $HOSTNAME
EOF
fi

API_LB_EP=0
ETCD_TLS=0
ETCD0_IP=0
ETCD1_IP=0
ETCD2_IP=0
INIT_CLUSTER=0
K8S_TLS=0
IMAGE_REPO=0
MASTER_IPS=0
VPC_CIDR=0
API_DNS=0
INSTALL_COMPLETE=0

# ensure iptables are used correctly
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# reset any existing iptables rules
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -F
sudo iptables -X

# master node IP addresses
while [ $MASTER_IPS -eq 0 ]; do
    if [ -f /tmp/master_ips ]; then
        MASTER_IPS=$(cat /tmp/master_ips)
    else
        echo "master ips not yet available"
        sleep 10
    fi
done

# VPC CIDR
while [ $VPC_CIDR -eq 0 ]; do
    if [ -f /tmp/vpc_cidr ]; then
        VPC_CIDR=$(cat /tmp/vpc_cidr)
    else
        echo "vpc cidr not yet available"
        sleep 10
    fi
done

sudo systemctl daemon-reload
sudo systemctl restart docker

# image repo to pull images from
while [ $IMAGE_REPO -eq 0 ]; do
    if [ -f /tmp/image_repo ]; then
        IMAGE_REPO=$(cat /tmp/image_repo)
    else
        echo "image repo not yet available"
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

# change pause image repo
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
Environment="KUBELET_NODE_ROLE=--node-labels=node-role.kubernetes.io/master="
Environment="KUBELET_INFRA_IMAGE=--pod-infra-container-image=${IMAGE_REPO}/pause-amd64:3.0"
Environment="KUBELET_CGROUPS=--cgroup-driver=systemd --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"
Environment="KUBELET_CLOUD_PROVIDER=--cloud-provider=aws"
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_CADVISOR_ARGS=--cadvisor-port=0"
Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_NODE_ROLE \$KUBELET_INFRA_IMAGE \$KUBELET_CGROUPS \$KUBELET_CLOUD_PROVIDER \$KUBELET_KUBECONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_DNS_ARGS \$KUBELET_AUTHZ_ARGS \$KUBELET_CADVISOR_ARGS \$KUBELET_CERTIFICATE_ARGS \$KUBELET_EXTRA_ARGS
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

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

# API DNS name
while [ $API_DNS -eq 0 ]; do
    if [ -f /tmp/api_dns ]; then
        API_DNS=$(cat /tmp/api_dns)
    else
        echo "API DNS not yet available"
        sleep 10
    fi
done

# generate kubeadm config
cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1alpha1
kind: MasterConfiguration
api:
  advertiseAddress: ${PRIVATE_IP}
  controlPlaneEndpoint: ${API_LB_EP}
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
- ${API_DNS}
apiServerExtraArgs:
  endpoint-reconciler-type: "lease"
  external-hostname: "${HOSTNAME}"
  admission-control: "Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,PersistentVolumeLabel,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota,MutatingAdmissionWebhook,ValidatingAdmissionWebhook"
  runtime-config: "admissionregistration.k8s.io/v1alpha1"
controllerManagerExtraArgs:
  configure-cloud-routes: "false"
kubernetesVersion: "1.9.7"
cloudProvider: "aws"
imageRepository: $IMAGE_REPO
nodeName: "${HOSTNAME}"
EOF

# get the K8s TLS assets from master0
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

# initialize
sudo kubeadm init --config=/tmp/kubeadm-config.yaml

# clean
while [ $INSTALL_COMPLETE -eq 0 ]; do
    if [ -f /tmp/install_complete ]; then
        sudo rm -rf /tmp/etc
        sudo rm /tmp/api_lb_ep \
            /tmp/etcd0_ip \
            /tmp/etcd1_ip \
            /tmp/etcd2_ip \
            /tmp/etcd_tls.tar.gz \
            /tmp/image_repo \
            /tmp/k8s_tls.tar.gz \
            /tmp/kubeadm-config.yaml
        INSTALL_COMPLETE=1
    else
        echo "cluster installation not yet complete"
        sleep 10
    fi
done

echo "bootstrap complete"
exit 0

