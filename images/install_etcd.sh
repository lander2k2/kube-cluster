#!/bin/bash

ETCD_VERSION=v3.1.10

sudo curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
sudo curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
sudo chmod +x /usr/local/bin/cfssl*

wget https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz -O /tmp/etcd.tar.gz
tar xvf /tmp/etcd.tar.gz -C /tmp
sudo mv /tmp/etcd-$ETCD_VERSION-linux-amd64/etcd /usr/local/bin/
sudo mv /tmp/etcd-$ETCD_VERSION-linux-amd64/etcdctl /usr/local/bin/
rm /tmp/etcd.tar.gz
rm -rf /tmp/etcd-$ETCD_VERSION-linux-amd64

