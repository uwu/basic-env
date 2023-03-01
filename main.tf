terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.14"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.1"
    }
  }
}

provider "coder" {}
data "coder_workspace" "me" {}

locals {
  friendly_shell_names = {
    "Bash" = "/bin/bash"
    "ZSH"  = "/usr/bin/zsh"
    "sh"   = "/bin/sh"
  }

  enable_subdomains = true
}

data "coder_parameter" "vnc" {
  name        = "VNC"
  description = "Do you want to enable VNC?"

  type    = "bool"
  default = "true"

  mutable = true
}

resource "random_string" "vnc_password" {
  count   = data.coder_parameter.vnc.value == "true" ? 1 : 0
  length  = 6
  special = false
}

resource "coder_metadata" "vnc_password" {
  count       = data.coder_parameter.vnc.value == "true" ? 1 : 0
  resource_id = random_string.vnc_password[0].id

  hide = true

  item {
    key = "description"
    value = "VNC Password"
  }
}

data "coder_parameter" "shell" {
  name        = "Shell"
  description = "Which shell do you want to be your default shell?"

  type    = "string"
  default = "bash"

  mutable = true

  option {
    name  = "Bash"
    value = "bash"
  }
  
  option {
    name  = "ZSH"
    value = "zsh"
  }

  option {
    name  = "sh"
    value = "sh"
  }

  /*validation {
    error = "Invalid shell!"
  }*/
}

data "coder_parameter" "dotfiles_repo" {
  name        = "Dotfiles"
  description = "Where are your [dotfiles](https://dotfiles.github.io) located at (git URL)?"

  type    = "string"

  mutable = true

  /*validation {
    error = "Invalid dotfiles URL!"
    regex = "https?:\\/\\/(www\\.)?[-a-zA-Z0-9@:%._\\+~#=]{1,256}\\.[a-zA-Z0-9()]{1,6}\\b([-a-zA-Z0-9()@:%_\\+.~#?&//=]*)"
  }*/
}

data "coder_parameter" "vscode_quality" {
  name        = "VSCode Quality"
  description = "Which VSCode channel do you want to use?"

  type    = "string"
  default = "stable"

  mutable = true

  option {
    name  = "Stable"
    value = "stable"
  }

  option {
    name  = "Insiders"
    value = "insiders"
  }

  option {
    name  = "Exploration"
    value = "exploration"
  }

  /*validation {
    error = "Invalid channel!"
  }*/
}

data "coder_parameter" "vscode_telemetry" {
  name        = "VSCode Telemetry level"
  description = "What telemetry level do you want VSCode to use?"

  type    = "string"
  default = "all"

  mutable = true

  option {
    name  = "None"
    value = "off"
  }

  option {
    name  = "Crash logs only"
    value = "crash"
  }

  option {
    name  = "Crash and error logs"
    value = "error"
  }

  option {
    name  = "Full"
    value = "all"
  }

  /*validation {
    error = "Invalid telemetry level!"
  }*/
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  env = {
    "DOTFILES_REPO" = data.coder_parameter.dotfiles_repo.value,
    "VNC_ENABLED"   = data.coder_parameter.vnc.value,
    "SHELL"         = data.coder_parameter.shell.value,

    "VSCODE_QUALITY" = data.coder_parameter.vscode_quality.value,
    "VSCODE_TELEMETRY_LEVEL" = data.coder_parameter.vscode_telemetry.value,

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
  echo "${data.coder_parameter.vnc.value == "true" ? random_string.vnc_password[0].result : 0}" | tightvncpasswd -f > $HOME/.vnc/passwd
  
  supervisorctl start vnc:*
fi
EOT
}

resource "coder_app" "supervisor" {
  agent_id = coder_agent.dev.id

  display_name = "Supervisor"
  slug         = "supervisor"

  url  = "http://localhost:8079"
  icon = "/icon/widgets.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "code-server" {
  agent_id = coder_agent.dev.id

  display_name = "VSCode"
  slug         = "code-server"

  url      = "http://localhost:8000/?folder=/home/coder/projects"
  icon     = "/icon/code.svg"

  subdomain = local.enable_subdomains
}

resource "coder_app" "novnc" {
  count    = data.coder_parameter.vnc.value == "true" ? 1 : 0
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
    key = "description"
    value = "Home volume"
  }
}

resource "docker_image" "basic_env" {
  name = "uwunet/basic-env:latest"

  build {
    context = "./docker"
    tag     = ["uwunet/basic-env", "uwunet/basic-env:latest", "uwunet/basic-env:v0.3"]
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
    key   = "description"
    value = "Container image"
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.basic_env.image_id

  name     = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)

  dns      = ["1.1.1.1"]

  entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]

  volumes { 
    volume_name    = docker_volume.home.name
    container_path = "/home/coder/"
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}
