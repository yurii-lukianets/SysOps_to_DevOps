#!/bin/bash
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
MEM=$(free -m | awk "/^Mem:/{printf \"%d,%d,%d\", \$2, \$3, \$7}")
SWAP=$(free -m | awk "/^Swap:/{printf \"%d,%d\", \$2, \$3}")
LOAD=$(uptime | awk -F"load average:" "{print \$2}" | xargs)
echo "$TIMESTAMP,$MEM,$SWAP,$LOAD" >> /var/log/mem-track.csv
tail -1440 /var/log/mem-track.csv > /tmp/mem-tail.csv && mv /tmp/mem-tail.csv /var/log/mem-track.csv
