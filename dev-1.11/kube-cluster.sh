#!/bin/bash

USAGE=$(cat << END
Usage: ./kube-cluster.sh [-h] /path/to/private/key

Provide the private key that will grant access to EC2 instances

This utility will deploy a test k8s cluster with 3 masters, etcd co-hosted on masters
Number of workers statically defined in terraform.tfvars
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

trusted_fetch() {
    SOURCE=$1
    DEST=$2
    scp -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SOURCE $DEST
}

trusted_send() {
    LOCAL_FILE=$1
    REMOTE_HOST=$2
    REMOTE_PATH=$3
    scp -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        $LOCAL_FILE ubuntu@$REMOTE_HOST:/tmp/tempfile
    ssh -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        ubuntu@$REMOTE_HOST "mv /tmp/tempfile $REMOTE_PATH"
}

set -e

# provision that action
terraform init infra
terraform apply -auto-approve infra

# collect terraform output
MASTER0=$(terraform output master0_ep)
MASTER0_IP=$(terraform output master0_ip)
API_LB_EP=$(terraform output api_lb_ep)
WORKERS=$(terraform output worker_ep)

# wait for infrastructure to spin up
echo "pausing for 3 min to allow infrastructure to spin up..."
sleep 180

if [ ! -d /tmp/kube-cluster ]; then
    mkdir /tmp/kube-cluster
fi

# distribute K8s API endpoint
echo "$API_LB_EP" > /tmp/kube-cluster/api_lb_ep
trusted_send /tmp/kube-cluster/api_lb_ep $MASTER0 /tmp/api_lb_ep
echo "k8s api endpoint distributed to master nodes"

# wait for master0 to initialize cluster
echo "pausing for 3 min to allow master initialization..."
sleep 180

# retreive K8s TLS assets
trusted_fetch ubuntu@$MASTER0:/tmp/k8s_tls.tar.gz /tmp/kube-cluster/
echo "k8s TLS assets retrieved"

# retreive kubeadm join command
trusted_fetch ubuntu@$MASTER0:/tmp/join /tmp/kube-cluster/join
echo "join command retreived"

# distribute join command to worker/s
for WORKER in $WORKERS; do
    trusted_send /tmp/kube-cluster/join $(echo $WORKER | tr -d ,) /tmp/join
done
echo "join command sent to worker/s"

rm -rf /tmp/kube-cluster

# grab the kubeconfig to use locally
trusted_fetch ubuntu@$MASTER0:~/.kube/config ./kubeconfig
sed -i -e "s/$MASTER0_IP/$API_LB_EP/g" ./kubeconfig

exit 0

