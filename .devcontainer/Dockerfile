FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    curl \
    git \
    build-essential \
    autoconf \
    libssl-dev \
    libncurses5-dev \
    inotify-tools \
    postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install asdf
USER vscode
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0 \
    && echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc \
    && echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc

# Install Erlang and Elixir via asdf
RUN bash -c 'source ~/.asdf/asdf.sh && \
    asdf plugin add erlang && \
    asdf plugin add elixir && \
    asdf install erlang 26.2.5 && \
    asdf install elixir 1.17.2-otp-26 && \
    asdf global erlang 26.2.5 && \
    asdf global elixir 1.17.2-otp-26 && \
    mix local.hex --force && \
    mix local.rebar --force'

USER root
