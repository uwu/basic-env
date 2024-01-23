FROM ubuntu:latest

USER root

ENV DEBIAN_FRONTEND="noninteractive"
RUN apt update -y && \
    apt install -y --no-install-recommends ca-certificates apt-transport-https software-properties-common wget gpg

# VSCode
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg && \
    install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg && \
    sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' && \
    rm -f packages.microsoft.gpg

# Basic tools
RUN apt update -y && \
    apt install -y   \
    curl git                 \
    bash zsh                 \
    code code-insiders nano  \
    sudo doas

# Create coder user
RUN useradd coder --create-home --shell=/bin/bash --uid=1000 --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd         && \
    echo "permit nopass coder as root" >> /etc/doas.conf

# X11 + VNC
RUN apt install -y --no-install-recommends \
    xfonts-base xfonts-100dpi xfonts-scalable \
    dbus-x11 x11-xserver-utils x11-utils      \
    xfwm4 xfdesktop4 xfconf libxfce4ui-utils  \
    xfce4-panel xfce4-session                 \
    xfce4-settings xfce4-terminal thunar      \
    psmisc xdg-utils                          \
    tigervnc-standalone-server tightvncpasswd \
    autocutsel websockify

# Supervisor
RUN apt install supervisor

ADD --chown=coder:coder --chmod=755 basic-env /usr/share/basic-env
WORKDIR /usr/share/basic-env

RUN rm -rf /etc/supervisor && \
    ln -s /usr/share/basic-env/supervisor /etc/supervisor

USER coder

# noVNC
RUN git clone https://github.com/novnc/noVNC && \
    mv noVNC/vnc.html noVNC/index.html

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

# Create a projects directory that way code-server doesn't have to spawn in the polluted mess that is /home/coder
RUN mkdir projects

# Add personalize file so the user knows they can run a script at each start
RUN echo "#!/bin/bash" > .personalize && \
    chmod +x .personalize

# Set default zshrc to avoid first use message
RUN cp /etc/zsh/newuser.zshrc.recommended $HOME/.zshrc

# Extensions gallery for code-server (Microsoft instead of OpenVSIX -> for when you use coder/code-server)
ENV EXTENSIONS_GALLERY='{"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","cacheUrl":"https://vscode.blob.core.windows.net/gallery/index","itemUrl":"https://marketplace.visualstudio.com/items","controlUrl":"","recommendationsUrl":""}'
ENV DEBIAN_FRONTEND="dialog"
ENV LANG="en_US.UTF-8"
