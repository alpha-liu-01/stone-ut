# Cross-build environment for mir-android2-platform (Ubuntu 24.04 host,
# arm64 target, UBports 24.04-2.x libraries). Used by
# tools/upstream/build-mir-android2-platform.sh.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
COPY ubports.gpg /usr/share/keyrings/ubports.gpg
RUN dpkg --add-architecture arm64 && \
    sed -i 's|^Types: deb|Types: deb\nArchitectures: amd64|' /etc/apt/sources.list.d/ubuntu.sources && \
    printf 'Types: deb\nArchitectures: arm64\nURIs: http://ports.ubuntu.com/ubuntu-ports/\nSuites: noble noble-updates noble-security\nComponents: main universe\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' > /etc/apt/sources.list.d/ports.sources && \
    echo 'deb [arch=arm64 signed-by=/usr/share/keyrings/ubports.gpg] http://repo.ubports.com/ 24.04-2.x main' > /etc/apt/sources.list.d/ubports.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends build-essential crossbuild-essential-arm64 cmake cmake-extras pkgconf \
        ca-certificates python3 protobuf-compiler capnproto \
        android-headers-28 libhardware-dev:arm64 libandroid-properties-dev:arm64 libhybris-dev:arm64 \
        libboost-program-options-dev:arm64 libegl1-mesa-dev:arm64 libgles2-mesa-dev:arm64 libglm-dev \
        libprotobuf-dev:arm64 libcapnp-dev:arm64 libgoogle-glog-dev:arm64 libgflags-dev:arm64 \
        liblttng-ust-dev:arm64 libudev-dev:arm64 libglib2.0-dev:arm64 libwayland-dev:arm64 libdeviceinfo-dev:arm64 \
        libmir1common-dev:arm64 libmir1platform-dev:arm64 libmir1core-dev:arm64 libmir1renderer-dev:arm64 \
        libmir1server-dev:arm64 libmir1client-dev:arm64 libmir1al-dev:arm64 mir1-renderer-gl-dev:arm64 && \
    rm -rf /var/lib/apt/lists/*
