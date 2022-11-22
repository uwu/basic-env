terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.3"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.23.0"
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

  enable_subdomains = true
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

variable "vscode_quality" {
  description = "Which VSCode channel do you want to use?"
  default     = "Stable"

  nullable = false

  validation {
    condition     = contains(["Stable", "Insiders", "Exploration"], var.vscode_quality)
    error_message = "Invalid channel!"
  }
}

variable "vscode_telemetry" {
  description = "Which telemetry level do you want to use for VSCode?"
  default     = "all"

  nullable = false

  validation {
    condition     = contains(["off", "crash", "error", "all"], var.vscode_telemetry)
    error_message = "Invalid telemetry level!"
  }
}

variable "vnc" {
  description = "Do you want to enable VNC?"
  default     = true

  nullable = false
  type     = bool
}

resource "random_string" "vnc_password" {
  count   = var.vnc == true ? 1 : 0
  length  = 6
  special = false
}

resource "coder_metadata" "vnc_password" {
  count       = var.vnc == true ? 1 : 0
  resource_id = random_string.vnc_password[0].id

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

    "VSCODE_QUALITY" = lower(var.vscode_quality),
    "VSCODE_TELEMETRY_LEVEL" = var.vscode_telemetry,

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
  sudo -u root $(which coder) dotfiles -y "$DOTFILES_REPO"
fi

supervisord

echo "[+] Starting code-server"
supervisorctl start code-server

if [ "$VNC_ENABLED" = "true" ]
then
  echo "[+] Starting VNC"
  echo "${var.vnc == true ? random_string.vnc_password[0].result : 0}" | tightvncpasswd -f > $HOME/.vnc/passwd
  
  supervisorctl start vnc:*
fi
EOT
}

resource "coder_app" "supervisor" {
  agent_id = coder_agent.dev.id

  display_name = "Supervisor"
  slug         = "supervisor"

  url      = "http://localhost:8079"
  icon     = "/icon/widgets.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "code-server" {
  agent_id = coder_agent.dev.id

  display_name = "VSCode"
  slug         = "code-server"

  url      = "http://localhost:8000/?folder=/home/coder"
  icon     = "/icon/code.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "novnc" {
  count    = var.vnc == true ? 1 : 0
  agent_id = coder_agent.dev.id

  display_name = "noVNC"
  slug         = "novnc"

  url      = "http://localhost:8081?autoconnect=1&resize=scale&path=@${data.coder_workspace.me.owner}/${data.coder_workspace.me.name}.dev/apps/noVNC/websockify&password=${random_string.vnc_password[0].result}"
  icon     = "/icon/novnc.svg"

  subdomain = local.enable_subdomains
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
    tag  = ["uwunet/basic-env", "uwunet/basic-env:latest", "uwunet/basic-env:v0.3"]
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
