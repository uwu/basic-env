FROM ubuntu:latest

USER 0

ENV DEBIAN_FRONTEND="noninteractive"
RUN apt update -y && \
    apt install -y apt-transport-https software-properties-common wget

# Git
RUN add-apt-repository ppa:git-core/ppa -y

# PowerShell
RUN wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" && \
    apt install -y ./packages-microsoft-prod.deb

# Dart
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" > /etc/apt/sources.list.d/dart_stable.list

# VSCode
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg && \
    install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg && \
    sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' && \
    rm -f packages.microsoft.gpg

RUN apt update -y

# Basic tools
RUN apt install -y \
    build-essential curl git \
    vim nano                 \
    man locales htop         \
    bash zsh powershell      \
    python3 python3-pip dart \
    ca-certificates          \
    zip unzip                \
    sudo doas

# VSCode
RUN apt install -y code code-insiders

# Create coder user
RUN useradd coder --create-home --shell=/bin/bash --uid=1000 --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd         && \
    echo "permit nopass coder as root" >> /etc/doas.conf

# X11 / VNC
RUN apt install -y --no-install-recommends \
    xfonts-base xfonts-100dpi xfonts-scalable \
    dbus-x11 x11-xserver-utils x11-utils      \
    xfce4 xfce4-goodies                       \
    psmisc xdg-utils                          \
    tigervnc-standalone-server tightvncpasswd \
    autocutsel websockify

# Supervisor
RUN apt install supervisor

ADD basic-env /usr/share/basic-env
WORKDIR /usr/share/basic-env

RUN rm -rf /etc/supervisor && \
    ln -s /usr/share/basic-env/supervisor /etc/supervisor

# noVNC
RUN git clone https://github.com/novnc/noVNC && \
    mv noVNC/vnc.html noVNC/index.html

RUN chown coder:coder /usr/share/basic-env -R && \
    chmod 755 /usr/share/basic-env -R

USER 1000
WORKDIR /home/coder

# VNC
RUN mkdir .vnc            && \
    touch .vnc/passwd     && \
    chmod 600 .vnc/passwd && \
    touch .Xresources     && \
    touch .Xauthority     && \
    mkdir .user-dirs

ADD --chown=coder:coder --chmod=700 xstartup /home/coder/.vnc/xstartup
ADD --chown=coder:coder user-dirs.dirs /home/coder/.config/user-dirs.dirs
RUN chmod +x /home/coder/.vnc/xstartup

# Create a projects directory that way code-server doesn't have to spawn in the polluted mess that is /home/coder
RUN mkdir projects

# Add personalize file so the user knows they can run a script at each start
RUN echo "#!/bin/bash" > .personalize && \
    chmod +x .personalize

# Set default zshrc to avoid first use message
RUN cp /etc/zsh/newuser.zshrc.recommended $HOME/.zshrc

# nvm + node + pnpm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
RUN export NVM_DIR="$HOME/.nvm" && \
    [ -s "$NVM_DIR/nvm.sh" ]    && \
    . "$NVM_DIR/nvm.sh"         && \
    nvm install node            && \
    npm i -g pnpm npm

# Install sdkman
RUN curl -s "https://get.sdkman.io" | bash

# Extensions gallery for code-server (Microsoft instead of OpenVSIX -> for when you use coder/code-server)
ENV EXTENSIONS_GALLERY='{"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","cacheUrl":"https://vscode.blob.core.windows.net/gallery/index","itemUrl":"https://marketplace.visualstudio.com/items","controlUrl":"","recommendationsUrl":""}'
ENV DEBIAN_FRONTEND="dialog"
ENV LANG="en_US.UTF-8"
