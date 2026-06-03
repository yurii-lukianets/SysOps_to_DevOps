# TODO & Warnings

## 🔴 Security — rotate/clean immediately
- [ ] **API key `821ac.............9a19904bb13c`** — plaintext in `docs/CHECKLIST.md` (lines 57, 116), exposed in git history. **Assume compromised.**
- [ ] **`k8s/kubeconfig-lab`** — full cluster kubeconfig with base64 private key. Removed from tracking. Keep in `.gitignore`.
- [ ] **`docs/aws-k3s-setup.md`** — contains AWS Access Key ID `AKI..........SER4` (line 44). Removed from tracking.
- [ ] **`.sonet_free.md`** — AWS account ID, region, private key paths discussed. Already untracked.

## 🟡 Hardcoded credentials (low risk, bad practice)
- [ ] `ansible/group_vars/devops_lab.yml`: `grafana_admin_password: de...`
- [ ] `docker/monitoring/docker-compose.yml`: `GF_SECURITY_ADMIN_PASSWORD=de...`
- [ ] `terraform/docker-stack/backend.tf`: MinIO `minioadmin / minioadmin123`

## ⚪ Cleanup / hygiene
- [ ] `monitoring/` directory removed — configs live in `docker/monitoring/` instead. Verify nothing broken.
- [ ] `terraform/docker-stack/terraform.tfstate` — exists locally but gitignored (state uses MinIO backend).
- [ ] `.continue/` — empty IDE extension dir, not tracked.

## ✅ Done this session
- [x] **Fail2ban** встановлено на AWS (t3.micro) — SSH jail, 3 спроби → 24h ban, ~20MB RAM
- [x] **OOM recovery** — stop/start інстанса, тепер 283Mi available
- [x] **Housekeeping** — `.gitignore` fix, `.gitattributes`, файли рознесено

## 📝 IDE / git config
- [ ] `.claude/settings.local.json` — local settings file, now in `.gitignore`.
- [ ] `.gitattributes` added for line ending normalization — run `git add --renormalize .` if switching branches.
