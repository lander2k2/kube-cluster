#!/bin/bash

sudo yum clean all
#sudo yum update -y
sudo yum clean all

# disable SELinux
sudo mv /tmp/selinux_config /etc/selinux/config

# disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker

#cd /tmp; tar xvf /tmp/kubernetes-node-linux-amd64.tar.gz
#sudo mv /tmp/kubernetes/node/bin/kubelet /usr/bin/
#sudo mv /tmp/kubernetes/node/bin/kubectl /usr/bin/
#sudo mv /tmp/kubernetes/node/bin/kubeadm /usr/bin/
#rm /tmp/kubernetes-node-linux-amd64.tar.gz
#rm -rf /tmp/kubernetes
#sudo mv /tmp/kubelet.service /lib/systemd/system/
#sudo mkdir /etc/systemd/system/kubelet.service.d/
#sudo systemctl enable kubelet

sudo tee -a /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
sudo yum install -y kubelet-1.9.7-0 kubeadm-1.9.7-0 kubectl-1.9.7-0
sudo systemctl enable kubelet

sudo curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl*

for pkg in $(ls /tmp/*_images.tar); do
    sudo docker load --input $pkg
done

