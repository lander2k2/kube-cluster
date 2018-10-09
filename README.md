# kube-cluster

This repo consists of tooling to assist in deploying Kubernetes clusters on AWS.  It may be useful for generating short-lived clusters.  Or you can build upon what's here to repeatably deploy clusters with your customized configurations.

How it works:

1. Use packer to build AMI's that contain bootstrap scripts that will use kubeadm to create a cluster

2. Use a shell script to trigger a `terraform apply` and then shuffle the various TLS and config assets between nodes

3. Use `terraform destroy` to tear it all down when finished

There are several variants.  Those prefixed with "dev" have a single master with etcd co-hosted (and happen to run on ubuntu).  Those prefixed with "ha" have 3 masters with dedicated etcd nodes (and happen to run on centos).

