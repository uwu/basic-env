terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.13.0"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

locals {
  enable_subdomains = true

  workspace_name = lower(data.coder_workspace.me.name)
  user_name = lower(data.coder_workspace.me.owner)

  images = {
    javascript = docker_image.javascript_image
    dart = docker_image.dart_image
    java = docker_image.java_image

    base = docker_image.base_image
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

provider "coder" {}
data "coder_workspace" "me" {}

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
}

data "coder_parameter" "dotfiles_repo" {
  name        = "Dotfiles"
  description = "Where are your [dotfiles](https://dotfiles.github.io) located at (git URL)?"

  type    = "string"

  mutable = true
}

data "coder_parameter" "vscode_binary" {
  name        = "VS Code Channel"
  description = "Which VS Code channel do you want to use?"

  type    = "string"
  default = "code"

  mutable = true

  option {
    name  = "Stable"
    value = "code"
  }

  option {
    name  = "Insiders"
    value = "code-insiders"
  }
}

data "coder_parameter" "docker_image" {
  name        = "Docker Image"
  description = "Which Docker image do you want to use?"

  type    = "string"
  default = "javascript"

  mutable = true

  option {
    name  = "JavaScript"
    value = "javascript"
  }

  option {
    name  = "Dart"
    value = "dart"
  }

  option {
    name  = "Java"
    value = "java"
  }

  option {
    name  = "Base"
    value = "base"
  }
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  env = {
    "DOTFILES_REPO" = data.coder_parameter.dotfiles_repo.value,
    "VNC_ENABLED"   = data.coder_parameter.vnc.value,
    "SHELL"         = data.coder_parameter.shell.value,

    "VSCODE_BINARY" = data.coder_parameter.vscode_binary.value,

    "SUPERVISOR_DIR" = "/usr/share/basic-env/supervisor"
  }

  startup_script = <<EOT
#!/bin/bash
echo "[+] Setting default shell"
SHELL=$(which $SHELL)
sudo chsh -s $SHELL $USER
sudo chsh -s $SHELL root

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

module "git-config" {
  source = "registry.coder.com/modules/git-config/coder"
  version = "1.0.0"
  agent_id = coder_agent.dev.id
  allow_username_change = true
  allow_email_change = true
}

module "coder-login" {
  source   = "registry.coder.com/modules/coder-login/coder"
  version  = "1.0.0"
  agent_id = coder_agent.dev.id
}

module "personalize" {
  source = "registry.coder.com/modules/personalize/coder"
  version = "1.0.0"
  agent_id = coder_agent.dev.id
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

  display_name = "VS Code Web"
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
  name = "coder-${data.coder_workspace.me.id}-home"

  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = local.user_name
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "coder_metadata" "home" {
  resource_id = docker_volume.home.id

  hide = true

  item {
    key = "description"
    value = "Home volume"
  }
}

resource "docker_image" "base_image" {
  count = 1
  name = "uwunet/basic-env-base:latest"

  build {
    context = "./docker/base"

    tag     = ["uwunet/basic-env-base", "uwunet/basic-env-base:latest", "uwunet/basic-env-base:v0.6"]
  }

  keep_locally = true
}

resource "docker_image" "javascript_image" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  name = "uwunet/basic-env-javascript:latest"

  build {
    context = "./docker/javascript"
    
    tag     = ["uwunet/basic-env-javascript", "uwunet/basic-env-javascript:latest", "uwunet/basic-env-javascript:v0.1"]
  }

  depends_on = [ docker_image.base_image[0] ]

  keep_locally = true
}

resource "docker_image" "dart_image" {
  count = data.coder_parameter.docker_image.value == "dart" ? 1 : 0

  name = "uwunet/basic-env-dart:latest"

  build {
    context = "./docker/dart"
    
    tag     = ["uwunet/basic-env-dart", "uwunet/basic-env-dart:latest", "uwunet/basic-env-dart:v0.1"]
  }

  depends_on = [ docker_image.base_image[0] ]

  keep_locally = true
}

resource "docker_image" "java_image" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  name = "uwunet/basic-env-java:latest"

  build {
    context = "./docker/java"
    
    tag     = ["uwunet/basic-env-java", "uwunet/basic-env-java:latest", "uwunet/basic-env-java:v0.1"]
  }

  depends_on = [ docker_image.base_image[0] ]

  keep_locally = true
}

resource "coder_metadata" "base_image" {
  resource_id = docker_image.base_image[0].id

  hide = true

  item {
    key   = "description"
    value = "Base container image"
  }
}

resource "coder_metadata" "javascript_image" {
  count = data.coder_parameter.docker_image.value == "javascript" ? 1 : 0

  resource_id = docker_image.javascript_image[0].id

  hide = true

  item {
    key   = "description"
    value = "JavaScript container image"
  }
}

resource "coder_metadata" "dart_image" {
  count = data.coder_parameter.docker_image.value == "dart" ? 1 : 0

  resource_id = docker_image.dart_image[0].id

  hide = true

  item {
    key   = "description"
    value = "Dart container image"
  }
}

resource "coder_metadata" "java_image" {
  count = data.coder_parameter.docker_image.value == "java" ? 1 : 0

  resource_id = docker_image.java_image[0].id

  hide = true

  item {
    key   = "description"
    value = "Java container image"
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  # we need to define a relation table in locals because we can't simply access resources like this: docker_image["javascript_image"]
  # we need to access [0] because we define a count in the docker_image's definition
  image = local.images[data.coder_parameter.docker_image.value][0].image_id

  name     = "coder-${local.user_name}-${local.workspace_name}"
  hostname = local.workspace_name

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

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = local.user_name
  }

  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }

  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
