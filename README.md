# kube-cluster

A utility to deploy Kubernetes clusters to AWS using kubeadm, terraform and packer.

This branch supports the following:
* installing into an existing VPC
* installing Kubernetes without access to the required package repositories
* use of an HTTP proxy for access from the cluster to the public internet
* using an image repo other than google container registry for pulling control plane images

## Prerequisites

* install [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* install [packer](https://www.packer.io/intro/getting-started/install.html)
* install [terraform](https://www.terraform.io/intro/getting-started/install.html)
* have an AWS account with a key pair you can use

## Overview

* Use packer to build CentOS-based images that have services installed that will bootstrap k8s using kubeadm.
* Use the kube-cluster.sh script to deploy the control plane with terraform and coordinate the bootstrapping.
* Use terraform to deploy the worker auto-scaling-group.
* Use terraform to tear down the cluster when finished.

There are five distinct roles:

* the `etcd0` node is the first etcd node deployed where etcd TLS assets are generated
* the `etcd` nodes are the additional etcd cluster members
* the `master0` node is the first master node deployed where the K8s TLS assets are generated
* the `master` nodes are added for HA
* the `worker` node/s are for workloads


## Usage

1. Clone this repo.
```
    $ git clone git@github.com:lander2k2/kube-cluster.git
    $ cd kube-cluster
```

2. Export your AWS keys and preferred region.
```
	$ export AWS_ACCESS_KEY_ID="accesskey"
	$ export AWS_SECRET_ACCESS_KEY="secretkey"
	$ export AWS_DEFAULT_REGION="us-east-2"
```

3. Create a tfvars file for terraform.
```
    $ cp terraform.tfvars.example terraform.tfvars
```

4. Open `terraform.tfvars` and add values for:
* `cluster_name`
* `key_name`
* `region`
* `primary_az`
* `secondary_az`

5. Deploy network for the cluster.
```
    $ cd network
    $ ln -s ../terraform.tfvars terraform.tfvars
    $ terraform init
    $ terraform plan  # to check what will be done
    $ terraform apply
    $ cd ../
```

6. Use the terraform output to add values in `terraform.tfvars` for:
* `vpc_id`
* `primary_subnet`
* `secondary_subnet`

6. Build your 5 machine images.  Note the AMI IDs as you build them and add to `terraform.tfvars`.  Lookup up the CentOS 7 AMI for your region here: https://wiki.centos.org/Cloud/AWS
```
	$ export SOURCE_AMI_ID=ami-123abc
    $ cd images
    $ packer build etcd0_template.json
    $ packer build etcd_template.json
    $ packer build master0_template.json
    $ packer build master_template.json
    $ packer build worker_template.json
    $ cd ../
```

7. Deploy the control plane.  This will stand up an etcd cluster and 3 master nodes.
```
    $ ./kube-cluster.sh centos [/path/to/private/key] [proxy_endpoint] [image_repo] [api_dns]
```

8. Check the control plane is ready.  A kubeconfig file will have been pulled down so you can use `kubectl` to check the cluster.  You should get ouput similar to below.
```
    $ export KUBECONFIG=$(pwd)/kubeconfig
    $ kubectl get nodes
    NAME               STATUS    ROLES     AGE       VERSION
    ip-172-31-6-106    Ready     master    20m       v1.9.7
    ip-172-31-6-2      Ready     master    28m       v1.9.7
    ip-172-31-7-202    Ready     master    20m       v1.9.7
```

9. Deploy the worker auto scaling group.
```
    $ cd workers
    $ ln -s ../terraform.tfvars terraform.tfvars
    $ terraform init
    $ terraform plan  # to check what will be done
    $ terraform apply
    $ cd ../
```

10. Tear down the cluster when you're finished with it.
```
    $ cd workers
    $ terraform destroy
    $ cd ../
    $ terraform destroy infra
    $ cd network
    $ terraform destroy
    $ cd ../
```

## Extend

### Machine Images
Change the machine images to suit your purposes.  Modify the files listed as needed, rebuild with packer and then update the AMI in your tfvars:

* ` [role]_template.json` - change the underlying OS or the files that are added to the image.
* `install_k8s.sh` - modify the packages that are installed on your nodes.
* `bootstrap_[role].sh - alter the bootstrapping operations to get k8s up and running.

### Infrastructure
Change the terraform configs to add/remove/change the AWS infrastructure that you need.

### kube-cluster script
This script coordinates the bootstrapping process by moving files between nodes.  Alter this script if you have to coordinate other operations between nodes.

## Kubernetes Version

The kubernetes binaries are not installed by pulling from the official package repo since that repo is not reachable from China.  Rather, they are installed as such:

1. Pull the node binaries from github.  A link can be found in the change logs in the kubernetes/kubernetes repo.  For example, if you want the node binaries for version 1.9.8, you can download it here: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.9.md#node-binaries

2. Put the tarball `kubernetes-node-linux-amd64.tar.gz` into the images directory when doinng a packer build of the node machine images.

Therefore changing the Kubernetes version used is done by:

1. Download the desired version tarball and using that to build the node's machine images.

2. Edit `images/bootstrap_master0_centos.sh` (line 217) and `images/bootstrap_master_centos.sh` (line 219) and change the kubernetes version in the kubeadm-config.

## Etcd Version

In order to change the version of etcd installed, set the `ETCD_VERSION` env variable at the top of the `images/install_etcd_centos.sh` file.

Refer to the External Dependencies section of the Kubernetes change log for the version of etcd to use with each Kubernetes version.  For example, the version of etcd to use with K8s 1.9 can be found here: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG-1.9.md#external-dependencies

