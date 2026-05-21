terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host     = "ssh://tst@192.168.100.203:7927"
  ssh_opts = ["-i", "~/.ssh/devops_lab", "-o", "StrictHostKeyChecking=no"]
}

# Portainer
resource "docker_image" "portainer" {
  name         = "portainer/portainer-ce:latest"
  keep_locally = true
}

resource "docker_container" "portainer" {
  name    = "portainer-tf"
  image   = docker_image.portainer.image_id
  restart = "unless-stopped"

  ports {
    internal = 9000
    external = 9001
  }

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
}