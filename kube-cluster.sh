#!/bin/bash

USAGE=$(cat << END
Usage: ./kube-cluster.sh [-h] /path/to/private/key
Provide the private key that will grant access to EC2 instances
This utility will deploy a test k8s cluster with 3 masters and one worker in AWS
END
)

if [ "$1" = "-h" ]; then
    echo "$USAGE"
    exit 0
elif [ "$1" = "" ]; then
    echo "Error: missing argument"
    echo "$USAGE"
    exit 1
fi

KEY_PATH=$1

if [ ! -f $KEY_PATH ]; then
    echo "Error: no file found at $KEY_PATH"
    echo "$USAGE"
    exit 1
fi

trusted_scp() {
    SOURCE=$1
    DEST=$2
    scp -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SOURCE $DEST
}

# provision that action
terraform init infra
terraform apply -auto-approve infra

# collect terraform output
MASTER0=$(terraform output master0_ep)
MASTER1=$(echo "$(terraform output master_ep)" | sed -n '1 p' | tr -d ,)
MASTER2=$(echo "$(terraform output master_ep)" | sed -n '2 p')
API_LB_EP=$(terraform output api_internal_lb_ep)
WORKER=$(terraform output worker_ep)

# wait for infrastructure to spin up
echo "pausing for 3 min to allow infrastructure to spin up..."
sleep 180

mkdir /tmp/kube-cluster

# distribute K8s API endpoint
echo "$API_LB_EP" > /tmp/kube-cluster/api_lb_ep
trusted_scp /tmp/kube-cluster/api_lb_ep ubuntu@$MASTER0:/tmp/
trusted_scp /tmp/kube-cluster/api_lb_ep ubuntu@$MASTER1:/tmp/
trusted_scp /tmp/kube-cluster/api_lb_ep ubuntu@$MASTER2:/tmp/
echo "k8s api endpoint distributed to master nodes"

# retrieve etcd TLS
trusted_scp ubuntu@$MASTER0:/tmp/etcd_tls.tar.gz /tmp/kube-cluster/
echo "etcd TLS assets retrieved"

# distribute etcd TLS
trusted_scp /tmp/kube-cluster/etcd_tls.tar.gz ubuntu@$MASTER1:/tmp/
trusted_scp /tmp/kube-cluster/etcd_tls.tar.gz ubuntu@$MASTER2:/tmp/
echo "etcd TLS assets distributed"

# collect etcd members
trusted_scp ubuntu@$MASTER0:/tmp/etcd_member /tmp/kube-cluster/etcd0
trusted_scp ubuntu@$MASTER1:/tmp/etcd_member /tmp/kube-cluster/etcd1
trusted_scp ubuntu@$MASTER2:/tmp/etcd_member /tmp/kube-cluster/etcd2
echo "$(cat /tmp/kube-cluster/etcd0),$(cat /tmp/kube-cluster/etcd1),$(cat /tmp/kube-cluster/etcd2)" > \
    /tmp/kube-cluster/init_cluster
echo "etcd members collected"

# distribute etcd initial cluster
trusted_scp /tmp/kube-cluster/init_cluster ubuntu@$MASTER0:/tmp/init_cluster
trusted_scp /tmp/kube-cluster/init_cluster ubuntu@$MASTER1:/tmp/init_cluster
trusted_scp /tmp/kube-cluster/init_cluster ubuntu@$MASTER2:/tmp/init_cluster
echo "initial etcd cluster distributed"

# collect private IPs for api server
trusted_scp ubuntu@$MASTER0:/tmp/private_ip /tmp/kube-cluster/etcd0_ip
trusted_scp ubuntu@$MASTER1:/tmp/private_ip /tmp/kube-cluster/etcd1_ip
trusted_scp ubuntu@$MASTER2:/tmp/private_ip /tmp/kube-cluster/etcd2_ip
echo "addon master IPs collected"

# distribute private IPs
trusted_scp /tmp/kube-cluster/etcd0_ip ubuntu@$MASTER0:/tmp/etcd0_ip
trusted_scp /tmp/kube-cluster/etcd1_ip ubuntu@$MASTER0:/tmp/etcd1_ip
trusted_scp /tmp/kube-cluster/etcd2_ip ubuntu@$MASTER0:/tmp/etcd2_ip
trusted_scp /tmp/kube-cluster/etcd0_ip ubuntu@$MASTER1:/tmp/etcd0_ip
trusted_scp /tmp/kube-cluster/etcd1_ip ubuntu@$MASTER1:/tmp/etcd1_ip
trusted_scp /tmp/kube-cluster/etcd2_ip ubuntu@$MASTER1:/tmp/etcd2_ip
trusted_scp /tmp/kube-cluster/etcd0_ip ubuntu@$MASTER2:/tmp/etcd0_ip
trusted_scp /tmp/kube-cluster/etcd1_ip ubuntu@$MASTER2:/tmp/etcd1_ip
trusted_scp /tmp/kube-cluster/etcd2_ip ubuntu@$MASTER2:/tmp/etcd2_ip

# wait for master0 to initialize cluster
echo "pausing for 8 min to allow master initialization..."
sleep 480

# retreive K8s TLS assets
trusted_scp ubuntu@$MASTER0:/tmp/k8s_tls.tar.gz /tmp/kube-cluster/
echo "k8s TLS assets retrieved"

# distribute K8s TLS assets
trusted_scp /tmp/kube-cluster/k8s_tls.tar.gz ubuntu@$MASTER1:/tmp/
trusted_scp /tmp/kube-cluster/k8s_tls.tar.gz ubuntu@$MASTER2:/tmp/
echo "k8s TLS assets distributed"

# retreive kubeadm join command
trusted_scp ubuntu@$MASTER0:/tmp/join /tmp/kube-cluster/join
echo "join command retreived"

# distribute join command to worker
trusted_scp /tmp/kube-cluster/join ubuntu@$WORKER:/tmp/join
echo "join command sent to worker"

rm -rf /tmp/kube-cluster

exit 0

