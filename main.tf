terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.4.2"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.18.1"
    }
  }
}

provider "coder" {}
data "coder_workspace" "me" {}

locals {
  friendly_shell_names = {
    "ZSH" = "/usr/bin/zsh"
    "Bash" = "/bin/bash"
    "sh" = "/bin/sh"
  }
}

variable "dotfiles_repo" {
  description = "Where are your dotfiles located at (git)?"
  default = ""

  #validation {
  #  condition     = can(regex("^(?:(?P<scheme>[^:/?#]+):)?(?://(?P<authority>[^/?#]*))?", var.dotfiles_repo)) || var.dotfiles_repo == ""
  #  error_message = "Invalid URL !"
  #}
}

variable "shell" {
  description = "Which shell do you want to be your default shell?"
  default = "Bash"

  nullable = false

  validation {
    condition     = contains(["ZSH", "Bash", "sh"], var.shell)
    error_message = "Invalid shell!"
  }
}

variable "vnc" {
  description = "Do you want to enable VNC?"
  default = "true"

  nullable = false

  validation {
    condition     = contains(["true", "false"], var.vnc)
    error_message = "Invalid answer (vnc)!"
  }
}

resource "coder_agent" "dev" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<EOT
code-server --auth none &

sudo chsh -s $SHELL coder
/home/coder/.personalize

if [ "$VNC_ENABLED" = "true" ]
then
  vncserver -localhost -geometry 1920x1080
  websockify 1337 localhost:5901 --web /usr/share/novnc &
fi
EOT
}

resource "coder_app" "code-server" {
  agent_id = coder_agent.dev.id
  name     = "VSCode"
  url      = "http://localhost:8080/?folder=/home/coder"
  icon     = "/icon/code.svg"
}

resource "coder_app" "novnc" {
  count    = var.vnc == "true" ? 1 : 0
  agent_id = coder_agent.dev.id
  name     = "noVNC"
  url      = "http://localhost:1337"
  icon     = "https://ppswi.us/noVNC/app/images/icons/novnc-icon.svg"
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-root"
}

resource "docker_image" "coder_image" {
  name = "coder-basic-env-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  build {
    path       = "./docker/"
    dockerfile = "Dockerfile"
    tag        = ["uwunetwork/basic-env:v0.1"]
  }

  keep_locally = true
}

resource "docker_container" "workspace" {
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  count = data.coder_workspace.me.start_count
  image = docker_image.coder_image.latest

  name     = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)
  dns      = ["1.1.1.1"]
  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = [
    "CODER_AGENT_TOKEN=${coder_agent.dev.token}",
    "EXTENSIONS_GALLERY={\"serviceUrl\":\"https://marketplace.visualstudio.com/_apis/public/gallery\",\"cacheUrl\":\"https://vscode.blob.core.windows.net/gallery/index\",\"itemUrl\":\"https://marketplace.visualstudio.com/items\",\"controlUrl\":\"\",\"recommendationsUrl\":\"\"}",
    "VNC_ENABLED=${var.vnc}",
    "SHELL=${lookup(local.friendly_shell_names, var.shell)}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}
