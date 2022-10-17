terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.5.3"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.22.0"
    }
  }
}

provider "coder" {}
data "coder_workspace" "me" {}

locals {
  friendly_shell_names = {
    "ZSH"  = "/usr/bin/zsh"
    "Bash" = "/bin/bash"
    "sh"   = "/bin/sh"
  }
}

variable "dotfiles_repo" {
  description = "Where are your dotfiles located at (git)?"
  default     = ""

  validation {
    condition     = can(regex("^(?:(?P<scheme>[^:/?#]+):)?(?://(?P<authority>[^/?#]*))?", var.dotfiles_repo)) || var.dotfiles_repo == ""
    error_message = "Invalid URL!"
  }
}

variable "shell" {
  description = "Which shell do you want to be your default shell?"
  default     = "Bash"

  nullable = false

  validation {
    condition     = contains(["ZSH", "Bash", "sh"], var.shell)
    error_message = "Invalid shell!"
  }
}

variable "vnc" {
  description = "Do you want to enable VNC?"
  default     = true

  nullable = false
  type     = bool
}

resource "random_string" "vnc_password" {
  length           = 6
  special          = false
}

resource "coder_metadata" "vnc_password" {
  resource_id = random_string.vnc_password.id

  hide = true

  item {
    key = "name"
    value = "vnc_password"
  }
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  env = {
    "DOTFILES_REPO" = var.dotfiles_repo,
    "VNC_ENABLED"   = var.vnc,
    "SHELL"         = lookup(local.friendly_shell_names, var.shell),

    "SUPERVISOR_DIR" = "/usr/share/basic-env/supervisor"
  }

  startup_script = <<EOT
#!/bin/bash
echo "[+] Setting default shell"
sudo chsh -s $SHELL coder
sudo chsh -s $SHELL root

echo "[+] Running personalize script"
$HOME/.personalize

if ! [ -z "$DOTFILES_REPO" ]; then
  echo "[+] Importing dotfiles"
  coder dotfiles -y "$DOTFILES_REPO"
fi

supervisord

echo "[+] Starting code-server"
supervisorctl start code-server

if [ "$VNC_ENABLED" = "true" ]
then
  echo "[+] Starting VNC"
  echo "${random_string.vnc_password.result}" | vncpasswd -f > $HOME/.vnc/passwd
  
  supervisorctl start vnc:*
fi
EOT
}

resource "coder_app" "supervisor" {
  agent_id = coder_agent.dev.id
  name     = "Supervisor"
  url      = "http://localhost:8079"
  icon     = "/icon/widgets.svg"
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
  url      = "http://localhost:8081?autoconnect=1&resize=scale&path=@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}.dev/apps/noVNC/websockify&password=${random_string.vnc_password.result}"
  icon     = "/icon/novnc-icon.svg"
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}-home"
}

resource "coder_metadata" "home" {
  resource_id = docker_volume.home.id

  hide = true

  item {
    key = "name"
    value = "home"
  }
}

resource "docker_image" "basic_env" {
  name = "uwunet/basic-env:latest"

  build {
    path = "./docker"
    tag  = ["uwunet/basic-env", "uwunet/basic-env:latest", "uwunet/basic-env:v0.2"]
  }

  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "docker/*") : filesha1(f)]))
  }

  keep_locally = true
}

resource "coder_metadata" "basic_env" {
  resource_id = docker_image.basic_env.id

  hide = true

  item {
    key   = "name"
    value = "basic_env"
  }
}

resource "docker_container" "workspace" {
  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  count = data.coder_workspace.me.start_count
  image = docker_image.basic_env.image_id

  name     = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  dns      = ["1.1.1.1"]

  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}
