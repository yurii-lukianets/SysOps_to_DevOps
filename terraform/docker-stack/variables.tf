variable "server_host" {
  description = "Ubuntu server IP"
  default     = "192.168.100.203"
}

variable "server_user" {
  description = "SSH user"
  default     = "tst"
}

variable "ssh_key_path" {
  description = "Path to SSH private key"
  default     = "~/.ssh/devops_lab"
}