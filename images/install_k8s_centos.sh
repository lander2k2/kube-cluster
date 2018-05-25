#!/bin/bash

sudo yum clean all
sudo yum update -y
sudo yum clean all

# disable SELinux
sudo mv /tmp/selinux_config /etc/selinux/config

sudo yum install -y docker
sudo systemctl enable docker

cd /tmp; tar xvf /tmp/kubernetes-node-linux-amd64.tar.gz
sudo mv /tmp/kubernetes/node/bin/kubelet /usr/bin/
sudo mv /tmp/kubernetes/node/bin/kubectl /usr/local/bin/
sudo mv /tmp/kubernetes/node/bin/kubeadm /usr/local/bin/
rm /tmp/kubernetes-node-linux-amd64.tar.gz
rm -rf /tmp/kubernetes
sudo mv /tmp/kubelet.service /lib/systemd/system/
sudo mkdir /etc/systemd/system/kubelet.service.d/
sudo systemctl enable kubelet

sudo curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl*

