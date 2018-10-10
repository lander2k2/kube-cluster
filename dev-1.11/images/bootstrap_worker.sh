#!/bin/bash

JOINED=0

while [ $JOINED -eq 0 ]; do
    if [ -f /tmp/join ]; then
        echo "Joining node to cluster..."
        sudo $(cat /tmp/join) --node-name=$(curl http://169.254.169.254/latest/meta-data/local-hostname)
        JOINED=1
    else
        echo "Join command not yet available - sleeping..."
        sleep 10
    fi
done

sudo mkdir -p /var/lib/kubelet/
sudo cat > /var/lib/kubelet/kubeadm-flags.env <<EOF
KUBELET_KUBEADM_ARGS=--cloud-provider=aws --cgroup-driver=cgroupfs --cni-bin-dir=/opt/cni/bin --cni-conf-dir=/etc/cni/net.d --network-plugin=cni
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

