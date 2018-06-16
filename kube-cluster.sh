#!/bin/bash

USAGE=$(cat << END
Install the control plane for a Kubnernetes cluster using packer, terraform and kubeadm

Usage: ./kube-cluster.sh [-h] </path/to/private/key> <proxy_endpoint> <image_repo> <api_dns>

Required Arguments:
/path/to/private/key - the local filepath to the ssh private key of the
named AWS key pair identified in the terraform.tfvars

proxy_endpoint - the endpoint for the HTTP proxy that will provide
access to the public internet for the cluster

image_repo - the image reposistory to pull images from when installing
cluster, e.g. quay.io/my_repo

api_dns - the URL that has been registered in DNS that will be used to connect to API
END
)

if [ "$1" = "-h" ]; then
    echo "$USAGE"
    exit 0
elif [ "$1" = "" ]; then
    echo "Error: missing private key argument"
    echo "$USAGE"
    exit 1
elif [ "$2" = "" ]; then
    echo "Error: missing proxy argument"
    echo "$USAGE"
    exit 1
elif [ "$3" = "" ]; then
    echo "Error: missing image repo argument"
    echo "$USAGE"
    exit 1
elif [ "$4" = "" ]; then
    echo "Error: missing api dns argument"
    echo "$USAGE"
    exit 1
fi

KEY_PATH=$1
PROXY_EP=$2
IMAGE_REPO=$3
API_DNS=$4

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
        $LOCAL_FILE centos@$REMOTE_HOST:/tmp/tempfile
    ssh -i $KEY_PATH -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        centos@$REMOTE_HOST "mv /tmp/tempfile $REMOTE_PATH"
}

set -e

# provision the control plane
terraform init infra
terraform apply -auto-approve infra

# collect terraform output
MASTER0_IP=$(terraform output master0_ip)
MASTER1_IP=$(echo "$(terraform output master_ip)" | sed -n '1 p' | tr -d ,)
MASTER2_IP=$(echo "$(terraform output master_ip)" | sed -n '2 p')
MASTER0=$(terraform output master0_ep)
MASTER1=$(echo "$(terraform output master_ep)" | sed -n '1 p' | tr -d ,)
MASTER2=$(echo "$(terraform output master_ep)" | sed -n '2 p')
API_LB_EP=$(terraform output api_lb_ep)
ETCD0=$(terraform output etcd0_ep)
ETCDS=$(terraform output etcd_ep)
ETCD0_IP=$(terraform output etcd0_ip)
ETCD_IPS=$(terraform output etcd_ip)
VPC_CIDR=$(terraform output vpc_cidr)

# wait for infrastructure to spin up
echo "pausing for 3 min to allow infrastructure to spin up..."
sleep 180

if [ ! -d /tmp/kube-cluster ]; then
    mkdir /tmp/kube-cluster
fi

# distribute VPC CIDR
echo "$VPC_CIDR" > /tmp/kube-cluster/vpc_cidr
VPC_CIDR=$(cat /tmp/kube-cluster/vpc_cidr)
trusted_send /tmp/kube-cluster/vpc_cidr $MASTER0 /tmp/vpc_cidr
trusted_send /tmp/kube-cluster/vpc_cidr $MASTER1 /tmp/vpc_cidr
trusted_send /tmp/kube-cluster/vpc_cidr $MASTER2 /tmp/vpc_cidr
echo "VPC cidr block distributed"

# distribute master IPs
echo "$MASTER0_IP,$MASTER1_IP,$MASTER2_IP" > /tmp/kube-cluster/master_ips
MASTER_IPS=$(cat /tmp/kube-cluster/master_ips)
trusted_send /tmp/kube-cluster/master_ips $MASTER0 /tmp/master_ips
trusted_send /tmp/kube-cluster/master_ips $MASTER1 /tmp/master_ips
trusted_send /tmp/kube-cluster/master_ips $MASTER2 /tmp/master_ips
echo "master IPs distributed to masters"


# distribute proxy endpoint to masters
echo "$PROXY_EP" > /tmp/kube-cluster/proxy_ep
trusted_send /tmp/kube-cluster/proxy_ep $MASTER0 /tmp/proxy_ep
trusted_send /tmp/kube-cluster/proxy_ep $MASTER1 /tmp/proxy_ep
trusted_send /tmp/kube-cluster/proxy_ep $MASTER2 /tmp/proxy_ep
echo "proxy endpoint sent to masters"

# distribute image repo to masters
echo "$IMAGE_REPO" > /tmp/kube-cluster/image_repo
trusted_send /tmp/kube-cluster/image_repo $MASTER0 /tmp/image_repo
trusted_send /tmp/kube-cluster/image_repo $MASTER1 /tmp/image_repo
trusted_send /tmp/kube-cluster/image_repo $MASTER2 /tmp/image_repo
echo "image repo sent to masters"

# distribute API DNS to masters
echo "$API_DNS" > /tmp/kube-cluster/api_dns
trusted_send /tmp/kube-cluster/api_dns $MASTER0 /tmp/api_dns
trusted_send /tmp/kube-cluster/api_dns $MASTER1 /tmp/api_dns
trusted_send /tmp/kube-cluster/api_dns $MASTER2 /tmp/api_dns
echo "API DNS name sent to masters"

# distribute K8s API endpoint
echo "$API_LB_EP" > /tmp/kube-cluster/api_lb_ep
trusted_send /tmp/kube-cluster/api_lb_ep $MASTER0 /tmp/api_lb_ep
trusted_send /tmp/kube-cluster/api_lb_ep $MASTER1 /tmp/api_lb_ep
trusted_send /tmp/kube-cluster/api_lb_ep $MASTER2 /tmp/api_lb_ep
echo "k8s api endpoint distributed to master nodes"

# retrieve etcd TLS
trusted_fetch centos@$ETCD0:/tmp/etcd_tls.tar.gz /tmp/kube-cluster/
echo "etcd TLS assets retrieved"

# distribute etcd TLS
for ETCD in $ETCDS; do
    trusted_send /tmp/kube-cluster/etcd_tls.tar.gz $(echo $ETCD | tr -d ,) /tmp/etcd_tls.tar.gz
done
trusted_send /tmp/kube-cluster/etcd_tls.tar.gz $MASTER0 /tmp/etcd_tls.tar.gz
trusted_send /tmp/kube-cluster/etcd_tls.tar.gz $MASTER1 /tmp/etcd_tls.tar.gz
trusted_send /tmp/kube-cluster/etcd_tls.tar.gz $MASTER2 /tmp/etcd_tls.tar.gz
echo "etcd TLS assets distributed"

# collect etcd members for the --initial-cluster flag on etcd
trusted_fetch centos@$ETCD0:/tmp/etcd_member /tmp/kube-cluster/init_cluster
INIT_MEMBERS=$(cat /tmp/kube-cluster/init_cluster)
for ETCD in $ETCDS; do
    trusted_fetch centos@$(echo $ETCD | tr -d ,):/tmp/etcd_member /tmp/kube-cluster/etcd_member
    INIT_MEMBERS="${INIT_MEMBERS},$(cat /tmp/kube-cluster/etcd_member)"
done
echo $INIT_MEMBERS > /tmp/kube-cluster/init_cluster
echo "etcd members collected"

# distribute etcd initial cluster
trusted_send /tmp/kube-cluster/init_cluster $ETCD0 /tmp/init_cluster
for ETCD in $ETCDS; do
    trusted_send /tmp/kube-cluster/init_cluster $(echo $ETCD | tr -d ,) /tmp/init_cluster
done
echo "initial etcd cluster distributed"

# sort out etcd ip addresses from terraform output
echo $ETCD0_IP > /tmp/kube-cluster/etcd0_ip
COUNTER=1
for ETCD_IP in $ETCD_IPS; do
    FILENAME="etcd${COUNTER}_ip"
    echo "$(echo $ETCD_IP | tr -d ,)" > /tmp/kube-cluster/$FILENAME
    let COUNTER=COUNTER+1
done

# distribute etcd member ip addresses
trusted_send /tmp/kube-cluster/etcd0_ip $MASTER0 /tmp/etcd0_ip
trusted_send /tmp/kube-cluster/etcd1_ip $MASTER0 /tmp/etcd1_ip
trusted_send /tmp/kube-cluster/etcd2_ip $MASTER0 /tmp/etcd2_ip
trusted_send /tmp/kube-cluster/etcd0_ip $MASTER1 /tmp/etcd0_ip
trusted_send /tmp/kube-cluster/etcd1_ip $MASTER1 /tmp/etcd1_ip
trusted_send /tmp/kube-cluster/etcd2_ip $MASTER1 /tmp/etcd2_ip
trusted_send /tmp/kube-cluster/etcd0_ip $MASTER2 /tmp/etcd0_ip
trusted_send /tmp/kube-cluster/etcd1_ip $MASTER2 /tmp/etcd1_ip
trusted_send /tmp/kube-cluster/etcd2_ip $MASTER2 /tmp/etcd2_ip
echo "etcd IP addresses distributed"

# wait for master0 to initialize cluster
echo "pausing for 3 min to allow master initialization..."
sleep 180

# retreive K8s TLS assets
trusted_fetch centos@$MASTER0:/tmp/k8s_tls.tar.gz /tmp/kube-cluster/
echo "k8s TLS assets retrieved"

# distribute K8s TLS assets
trusted_send /tmp/kube-cluster/k8s_tls.tar.gz $MASTER1 /tmp/k8s_tls.tar.gz
trusted_send /tmp/kube-cluster/k8s_tls.tar.gz $MASTER2 /tmp/k8s_tls.tar.gz
echo "k8s TLS assets distributed"

# retreive kubeadm join command
trusted_fetch centos@$MASTER0:/tmp/join /tmp/kube-cluster/join
JOIN_CMD=$(cat /tmp/kube-cluster/join)
echo "join command retreived"

# grab the kubeconfig to use locally
trusted_fetch centos@$MASTER0:~/.kube/config ./kubeconfig
sed -i -e "s/$MASTER0_IP/$API_LB_EP/g" ./kubeconfig
echo "kubeconfig retrieved"

# generate user data script for worker asg
if [ ! -d /tmp/kube-workers ]; then
    mkdir /tmp/kube-workers
fi
cat > /tmp/kube-workers/worker-bootstrap.sh <<EOF
#cloud-boothook
#!/bin/bash
echo "$PROXY_EP" | tee /tmp/proxy_ep
echo "$IMAGE_REPO" | tee /tmp/image_repo
echo "$JOIN_CMD" | tee /tmp/join
echo "$MASTER_IPS" | tee /tmp/master_ips
echo "$VPC_CIDR" | tee /tmp/vpc_cidr
echo "$API_LB_EP" | tee/tmp/api_lb_ep
EOF
echo "worker user data script generated"

# signal install complete
echo "complete" > /tmp/kube-cluster/install_complete
trusted_send /tmp/kube-cluster/install_complete $ETCD0 /tmp/install_complete
for ETCD in $ETCDS; do
    trusted_send /tmp/kube-cluster/install_complete $(echo $ETCD | tr -d ,) /tmp/install_complete
done
trusted_send /tmp/kube-cluster/install_complete $MASTER0 /tmp/install_complete
trusted_send /tmp/kube-cluster/install_complete $MASTER1 /tmp/install_complete
trusted_send /tmp/kube-cluster/install_complete $MASTER2 /tmp/install_complete

# clean
rm -rf /tmp/kube-cluster

exit 0

