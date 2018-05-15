#!/bin/bash

JOINED=0
PROXY_EP=0

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

