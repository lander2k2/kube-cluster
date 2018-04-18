#!/bin/bash

JOINED=0

while [ $JOINED -eq 0 ]; do
    if [ -f /tmp/join ]; then
        echo "Joining node to cluster..."
        sudo $(cat /tmp/join)
        JOINED=1
    else
        echo "Join command not yet available - sleeping..."
        sleep 10
    fi
done

