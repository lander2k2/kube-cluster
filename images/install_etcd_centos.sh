#!/bin/bash

ETCD_VERSION=v3.1.10

sudo yum clean all
sudo yum update -y
sudo yum clean all

# disable SELinux
sudo mv /tmp/selinux_config /etc/selinux/config

sudo curl -o /usr/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/bin/cfssl*

curl -sSL https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz | sudo tar -xzv --strip-components=1 -C /usr/local/bin/
rm -rf etcd-$ETCD_VERSION-linux-amd64*

