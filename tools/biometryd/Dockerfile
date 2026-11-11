FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
COPY ubports.gpg /usr/share/keyrings/ubports.gpg
RUN dpkg --add-architecture arm64 && \
    sed -i 's|^Types: deb|Types: deb\nArchitectures: amd64|' /etc/apt/sources.list.d/ubuntu.sources && \
    printf 'Types: deb\nArchitectures: arm64\nURIs: http://ports.ubuntu.com/ubuntu-ports/\nSuites: noble noble-updates noble-security\nComponents: main universe\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' > /etc/apt/sources.list.d/ports.sources && \
    echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubports.gpg] http://repo.ubports.com/ 24.04-2.x main' > /etc/apt/sources.list.d/ubports.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends build-essential crossbuild-essential-arm64 cmake cmake-extras pkgconf \
        qtbase5-dev-tools qtdeclarative5-dev-tools ca-certificates \
        libapparmor-dev:arm64 libboost-filesystem-dev:arm64 libboost-program-options-dev:arm64 libboost-test-dev:arm64 \
        libdbus-1-dev:arm64 libdbus-cpp-dev:arm64 libelf-dev:arm64 libgbinder-dev:arm64 libglib2.0-dev:arm64 \
        libglibutil-dev:arm64 libprocess-cpp-dev:arm64 libsqlite3-dev:arm64 nlohmann-json3-dev \
        qtbase5-dev:arm64 qtdeclarative5-dev:arm64 libgtest-dev:arm64 googletest:arm64 && \
    rm -rf /var/lib/apt/lists/*
