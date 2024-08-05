FROM ghcr.io/uwu/basic-env/base:latest

USER root

# Install requirements
RUN DEBIAN_FRONTEND="noninteractive" apt install -y zip unzip

USER coder

# Install sdkman
RUN curl -s "https://get.sdkman.io" | bash