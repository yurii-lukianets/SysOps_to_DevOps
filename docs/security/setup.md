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

## CrowdSec Verdict (AWS)

**CrowdSec on t3.micro — not viable.** Requires ~120-200MB additional RAM; only ~100-283Mi available after K3s + Prometheus.

→ AWS uses **Fail2ban** (SSH jail, ~20MB RAM) instead.
→ SG already locked to Cloudflare IPs for 80/443.

## Maintenance
sudo cscli alerts list
sudo cscli decisions list
sudo cscli metrics
