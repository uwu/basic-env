FROM codercom/code-server:latest

EXPOSE 1337

USER 0
ENV USER=root
RUN apt update
RUN apt install xfonts-base xfonts-100dpi                 \
    dbus-x11 psmisc xdg-utils x11-xserver-utils x11-utils \
    xfce4 xfce4-goodies                                   \
    tightvncserver autocutsel                             \
    novnc -y --no-install-recommends
ADD novnc/index.html /usr/share/novnc/index.html
ADD novnc/webutil.js /usr/share/novnc/app/webutil.js

USER 1000
ENV USER=coder
WORKDIR /home/coder
RUN mkdir $HOME/.vnc                                 && \
    touch $HOME/.vnc/passwd                          && \
    echo "uwunet" | vncpasswd -f > $HOME/.vnc/passwd && \
    chmod 600 $HOME/.vnc/passwd                      && \
    touch $HOME/.Xresources                          && \
    touch $HOME/.Xauthority                          && \
    mkdir $HOME/.user-dirs

ADD --chown=coder xstartup /home/coder/.vnc/xstartup
ADD --chown=coder user-dirs.dirs /home/coder/.config/user-dirs.dirs 

RUN chmod +x /home/coder/.vnc/xstartup

#ENTRYPOINT ["/usr/bin/entrypoint.sh" "--bind-addr" "0.0.0.0:8080" "."]