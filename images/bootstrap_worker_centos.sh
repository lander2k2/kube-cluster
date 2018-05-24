#!/bin/bash

JOINED=0
PROXY_EP=0
IMAGE_REPO=0

# proxy vars for docker
while [ $PROXY_EP -eq 0 ]; do
    if [ -f /tmp/proxy_ep ]; then
        PROXY_EP=$(cat /tmp/proxy_ep)
    else
        echo "proxy endpoint not yet available"
        sleep 10
    fi
done

sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat > /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://$PROXY_EP:3128/" "HTTPS_PROXY=http://$PROXY_EP:3128/"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# image repo to pull images from
while [ $IMAGE_REPO -eq 0 ]; do
    if [ -f /tmp/image_repo ]; then
        IMAGE_REPO=$(cat /tmp/image_repo)
    else
        echo "image repo not yet available"
        sleep 10
    fi
done

# change pause image repo
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf <<EOF
[Service]
Environment="KUBELET_INFRA_IMAGE=--pod-infra-container-image=${IMAGE_REPO}/pause-amd64:3.0"
Environment="KUBELET_CGROUP_DRIVER=--cgroup-driver=systemd"
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_CADVISOR_ARGS=--cadvisor-port=0"
Environment="KUBELET_CERTIFICATE_ARGS=--rotate-certificates=true --cert-dir=/var/lib/kubelet/pki"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_INFRA_IMAGE \$KUBELET_CGROUP_DRIVER \$KUBELET_KUBECONFIG_ARGS \$KUBELET_SYSTEM_PODS_ARGS \$KUBELET_NETWORK_ARGS \$KUBELET_DNS_ARGS \$KUBELET_AUTHZ_ARGS \$KUBELET_CADVISOR_ARGS \$KUBELET_CERTIFICATE_ARGS \$KUBELET_EXTRA_ARGS
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# run kubeadm join
while [ $JOINED -eq 0 ]; do
    if [ -f /tmp/join ]; then
        echo "Joining node to cluster..."
        HTTP_PROXY=http://$PROXY_EP:3128 \
            http_proxy=http://$PROXY_EP:3128 \
            HTTPS_PROXY=http://$PROXY_EP:3128 \
            https_proxy=http://$PROXY_EP:3128 \
            NO_PROXY=10.0.0.0/16,192.168.0.0/16 \
            no_proxy=10.0.0.0/16,192.168.0.0/16 \
            sudo -E bash -c '$(cat /tmp/join)'
        JOINED=1
    else
        echo "Join command not yet available - sleeping..."
        sleep 10
    fi
done

