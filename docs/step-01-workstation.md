# Step 1: Windows Workstation Setup

## Tools installed
- Git for Windows 2.x + GitBash
- PowerShell 5.1 / Windows Terminal
- VS Code with profile SysOps_to_DevOps
  - Remote SSH, Docker, GitLens, Git Graph extensions
- WSL2 (default version 2)

## SSH configuration
- Key type: ed25519
- Config: ~/.ssh/config with Host devops-lab alias
- Server: 192.168.100.203, port 7927, user tst

## Notes
- SSH key also added to GitHub (devops-lab-win)
- VS Code Remote SSH connects to Ubuntu 22.04 server