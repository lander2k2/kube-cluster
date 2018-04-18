#!/bin/bash

sudo chmod +x /tmp/bootstrap_$ROLE.sh
sudo mv /tmp/bootstrap_$ROLE.sh /usr/local/bin/
sudo mv /tmp/bootstrap-$ROLE.service /etc/systemd/system/
sudo chown root:root /etc/systemd/system/bootstrap-$ROLE.service

sudo systemctl enable bootstrap-$ROLE

