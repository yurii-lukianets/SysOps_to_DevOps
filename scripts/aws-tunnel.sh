#!/bin/bash
# AWS tunnel keeper — run every 5 min via cron
TUNNEL_PID=$(pgrep -f '9092:10.43.1.187' 2>/dev/null)
if [ -z "$TUNNEL_PID" ]; then
    ssh -i ~/.ssh/aws_k3s \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -f -L 0.0.0.0:9092:10.43.1.187:9090 \
        -N ubuntu@13.49.255.149
    echo "Tunnel started at $(date)" >> ~/aws-tunnel.log
fi
