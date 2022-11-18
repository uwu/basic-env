FROM codercom/code-server:latest

USER 0
RUN apt update

# Basic tools
RUN apt install wget zip unzip -y

# Install code-server
RUN wget -O- https://aka.ms/install-vscode-server/setup.sh | sh

# X11 / VNC
RUN apt install xfonts-base xfonts-100dpi                 \
    dbus-x11 psmisc xdg-utils x11-xserver-utils x11-utils \
    xfce4 xfce4-goodies xfonts-scalable                   \
    tigervnc-standalone-server autocutsel                 \
    websockify -y --no-install-recommends

# Supervisor
RUN apt install supervisor

ADD basic-env /usr/share/basic-env
WORKDIR /usr/share/basic-env

RUN rm -rf /etc/supervisor                                && \
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

# Extensions gallery for code-server (Microsoft instead of OpenVSIX)
ENV EXTENSIONS_GALLERY='{"serviceUrl":"https://marketplace.visualstudio.com/_apis/public/gallery","cacheUrl":"https://vscode.blob.core.windows.net/gallery/index","itemUrl":"https://marketplace.visualstudio.com/items","controlUrl":"","recommendationsUrl":""}'
