# kube-cluster

A utility to deploy test Kubernetes clusters to AWS using kubeadm, terraform and packer.

Note: This is experimental and does not deploy production-ready clusters.  The primary purppose for this repo is to spin up test clusters but can also be used as a starting point to automate the deployment of production-ready clusters or for platforms besides AWS.

The Kubernetes community is still refining the management of cluster lifecycles.  This repo simply offers a convenience until those processes are refined.

## Prerequisites

* install [packer](https://www.packer.io/intro/getting-started/install.html)
* install [terraform](https://www.terraform.io/intro/getting-started/install.html)
* have an AWS account with a key pair you can use

## Overview

* Use packer to build Ubuntu-based images that have services installed that will bootstrap k8s using kubeadm.
* Use the kube-cluster.sh script to deploy infrastructure with terraform and coordinate the bootstrapping.
* Use terraform to tear down the cluster when finished.

Note: the current setup here uses a 3-node etcd cluster co-located on the master nodes with the k8s control plane.

There are three distinct roles:
* the `master0` node is the first master node deployed
* the two `master` nodes are added for HA
* the `worker` node is for workloads

## Usage

1. Clone this repo.
```
    $ git clone git@github.com:lander2k2/kube-cluster.git
    $ cd kube-cluster
```

2. Export your AWS keys and preferred region.
```
    $ export TF_VAR_access_key="[your access key]"
    $ export TF_VAR_secret_key="[your secret key]"
    $ export TF_VAR_region="[your region]"
```

3. Create a tfvars file for terraform.
```
    $ cp terraform.tfvars.example terraform.tfvars
```

4. Open `terraform.tfvars` and add your key pair name.

5. Build your 3 machine images.  Note the AMI IDs as you build them and add to `terraform.tfvars`.
```
    $ cd images
    $ packer build master0_template.json
    $ packer build master_template.json
    $ packer build worker_template.json
```

6. Deploy the cluster.  Go and make coffee.  When you get back you will have a k8s cluster if everything went to plan.
```
    $ cd ../
    $ ./kube-cluster.sh /path/to/private/key
```

7. Check that your cluster is ready.  You should get ouput similar to below.
```
    $ ssh -i /path/to/private/key ubuntu@$(terraform output master0_ep)
    $ kubectl get nodes
    NAME               STATUS    ROLES     AGE       VERSION
    ip-172-31-13-245   Ready     <none>    21m       v1.10.1
    ip-172-31-6-106    Ready     master    20m       v1.10.1
    ip-172-31-6-2      Ready     master    28m       v1.10.1
    ip-172-31-7-202    Ready     master    20m       v1.10.1
```

8. Tear down the cluster when you're finished with it.
```
    $ terraform destroy infra
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

### Dedicated etcd
If you need to run a dedicated etcd cluster, you will need to create new image builds and terraform configs for the etcd nodes.

## TODO
* pull down kubeconfig to use locally
* expand to support multiple workers
* clean up tmp files on servers after install

