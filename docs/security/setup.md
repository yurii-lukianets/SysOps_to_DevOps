# Security Stack

## Layers
1. Cloudflare WAF — DDoS, GeoIP, WAF rules
2. iptables — only Cloudflare IPs on 80/443
3. CrowdSec — behavioral detection + auto-ban
4. crowdsec-firewall-bouncer-iptables — enforcement

## CrowdSec Collections
- crowdsecurity/traefik
- crowdsecurity/http-cve
- crowdsecurity/linux
- crowdsecurity/sshd

## GoAccess Stats
- URL: http://192.168.100.203:9080
- Updates: every 5 min via cron
- GeoIP: DB-IP country database

## Maintenance
sudo cscli alerts list
sudo cscli decisions list
sudo cscli metrics
