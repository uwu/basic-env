FROM uwunet/basic-env-base:latest

USER root

ENV DEBIAN_FRONTEND="noninteractive"
RUN wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" > /etc/apt/sources.list.d/dart_stable.list && \
    apt update -y && \
    apt install -y dart

USER coder
ENV DEBIAN_FRONTEND="dialog"