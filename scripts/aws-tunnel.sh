#!/bin/bash
# AWS tunnel keeper — run every 5 min via cron
# Tunnels AWS node-exporter (port 9100) to localhost:9101 for local Prometheus
TUNNEL_PID=$(pgrep -f '9101:172.31.39.148:9100' 2>/dev/null)
if [ -z "$TUNNEL_PID" ]; then
    ssh -i ~/.ssh/aws_k3s \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -f -L 0.0.0.0:9101:172.31.39.148:9100 \
        -N ubuntu@13.49.255.149
    echo "Tunnel started at $(date)" >> ~/aws-tunnel.log
fi
