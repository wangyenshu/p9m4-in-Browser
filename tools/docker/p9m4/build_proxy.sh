#!/bin/bash
set -e

# =================CONFIGURATION=================
IMAGE_TAG="p9m4-32bit-builder"
CONTAINER_NAME="p9m4-builder-tmp"
BUILDER_NAME="p9m4-proxy-builder"
PROXY_PORT=7897
IMAGES="$(dirname "$0")"/../../../images
OUT_ROOTFS_TAR="$IMAGES"/debian-9p-rootfs.tar
OUT_ROOTFS_FLAT="$IMAGES"/debian-9p-rootfs-flat
OUT_FSJSON="$IMAGES"/debian-base-fs.json

# DETECT HOST IP
HOST_IP=$(hostname -I | awk '{print $1}')

if [ -z "$HOST_IP" ]; then
    echo "Error: Could not detect Host IP. Please set HOST_IP manually in the script."
    exit 1
fi

PROXY_URL="http://${HOST_IP}:${PROXY_PORT}"
# ===============================================

# Cleanup
rm -f Dockerfile.32bit
mkdir -p "$IMAGES"

echo "Generating Dockerfile..."

# Generate 32-bit Dockerfile
cat <<EOF > Dockerfile.32bit
FROM i386/debian:stretch-slim

WORKDIR /root/build
ENV DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------
# ENABLE PROXY FOR ENTIRE BUILD (Including archive.debian.org)
# -----------------------------------------------------------
ARG PROXY_URL
ENV http_proxy=\${PROXY_URL}
ENV https_proxy=\${PROXY_URL}
ENV HTTP_PROXY=\${PROXY_URL}
ENV HTTPS_PROXY=\${PROXY_URL}

# 1. Base Setup (Point to the Debian Archive for Legacy Stretch)
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until && \\
    rm -f /etc/apt/sources.list.d/* && \\
    echo "deb http://archive.debian.org/debian/ stretch main contrib non-free" > /etc/apt/sources.list && \\
    apt-get update && \\
    apt-get install -y --allow-downgrades --no-install-recommends \\
    linux-image-686 \\
    libsystemd0=232-25+deb9u12 \\
    libudev1=232-25+deb9u12 \\
    systemd \\
    systemd-sysv \\
    locales \\
    libterm-readline-perl-perl \\
    && rm -rf /var/lib/apt/lists/*

# 2. Configure Locales & Shell
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \\
    locale-gen && \\
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \\
    chsh -s /bin/bash root  

# 3. Install Minimal X11, Input Drivers, Fonts, UI Libraries, and Python 2/WX dependencies
RUN apt-get update && \\
    apt-get install -y --no-install-recommends \\
    xserver-xorg-core xserver-xorg-video-fbdev xinit fluxbox \\
    xserver-xorg-input-mouse xserver-xorg-input-kbd xserver-xorg-input-evdev \\
    libxext6 libxrender1 libxtst6 libxi6 libx11-xcb1 libxrender-dev \\
    libfontconfig1 fonts-dejavu-core \\
    wget tar ca-certificates xterm \\
    python python-wxgtk3.0 \\
    && rm -rf /var/lib/apt/lists/*

# 4. Install Prover9-Mace4 (p9m4) GUI
COPY p9m4-v05.tar.gz /tmp/p9m4.tar.gz
RUN mkdir -p /opt && \\
    tar -xzf /tmp/p9m4.tar.gz -C /opt && \\
    rm /tmp/p9m4.tar.gz

# Reset Proxy (So it doesn't break networking inside the v86 emulator later)
ENV http_proxy=""
ENV https_proxy=""
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

RUN passwd -d root && \\
    sed -i 's/nullok_secure/nullok/' /etc/pam.d/common-auth

# 6. Configure Serial Console
# (Assuming getty-noclear.conf etc. are in the same directory as this script)
COPY getty-noclear.conf getty-override.conf /etc/systemd/system/getty@tty1.service.d/
COPY getty-autologin-serial.conf /etc/systemd/system/serial-getty@ttyS0.service.d/

RUN systemctl mask console-getty.service && \\
    systemctl enable serial-getty@ttyS0.service

# 7. Disable Unnecessary Services
RUN systemctl disable systemd-timesyncd.service && \\
    systemctl disable apt-daily.timer && \\
    systemctl disable apt-daily-upgrade.timer

# ------------------------------------------------------------------------------
# 8. 9p Filesystem Boot Configuration
# ------------------------------------------------------------------------------
RUN printf '%s\n' 9p 9pnet 9pnet_virtio virtio virtio_ring virtio_pci | tee -a /etc/initramfs-tools/modules

RUN echo '#!/bin/sh' > /etc/initramfs-tools/scripts/boot-9p && \\
    echo 'case \$1 in prereqs) exit 0;; esac' >> /etc/initramfs-tools/scripts/boot-9p && \\
    echo '. /scripts/functions' >> /etc/initramfs-tools/scripts/boot-9p && \\
    echo 'mkdir -p \${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \\
    echo 'mount -n -t 9p -o trans=virtio,version=9p2000.L,cache=loose,rw host9p \${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \\
    chmod +x /etc/initramfs-tools/scripts/boot-9p

RUN echo 'BOOT=boot-9p' | tee -a /etc/initramfs-tools/initramfs.conf
RUN update-initramfs -u

# 9. Configure X11 and Auto-start
RUN echo 'cd /opt/p9m4-v05 && python prover9-mace4.py & \n\
(sleep 5 && echo -e "\n\nGUI_READY\n" > /dev/ttyS0) & \n\
exec fluxbox' > /root/.xinitrc

RUN { \\
    echo 'if [ -z "\$DISPLAY" ]; then'; \\
    echo '  echo "127.0.0.1 localhost" > /etc/hosts'; \\
    echo '  echo "localhost" > /etc/hostname'; \\
    echo '  hostname localhost'; \\
    echo '  startx -- -ac'; \\
    echo 'fi'; \\
} >> /root/.bashrc

# 10. Force Xorg to use the FBDEV driver
RUN mkdir -p /etc/X11/xorg.conf.d && \\
    echo 'Section "Device"\n\
    Identifier "Card0"\n\
    Driver "fbdev"\n\
EndSection' > /etc/X11/xorg.conf.d/10-fbdev.conf

WORKDIR /root
EOF

# Build the Image
echo "--------------------------------------------------------"
echo "Building Docker Image..."
echo "Detected Host IP: $HOST_IP"
echo "Proxy activated for apt-get and downloads: $PROXY_URL"
echo "--------------------------------------------------------"
echo "Ensure 'Allow LAN' is ENABLED in Clash!"
echo "--------------------------------------------------------"

# 1. Clean up old builder
docker buildx rm "$BUILDER_NAME" 2>/dev/null || true

# 2. Configure builder with Proxy so it can pull the base image
docker buildx create \
  --name "$BUILDER_NAME" \
  --driver docker-container \
  --driver-opt env.BUILDKIT_STEP_LOG_MAX_SIZE=-1 \
  --driver-opt env.BUILDKIT_STEP_LOG_MAX_SPEED=-1 \
  --driver-opt env.http_proxy="$PROXY_URL" \
  --driver-opt env.https_proxy="$PROXY_URL" \
  --use

docker buildx build \
    --load \
    --progress=plain \
    --platform linux/386 \
    -f Dockerfile.32bit \
    -t "$IMAGE_TAG" \
    --build-arg PROXY_URL="$PROXY_URL" \
    .

# Export Docker
docker rm -f "$CONTAINER_NAME" || true
docker create --platform linux/386 --name "$CONTAINER_NAME" "$IMAGE_TAG"
docker export "$CONTAINER_NAME" > "$OUT_ROOTFS_TAR"

rm Dockerfile.32bit

echo "Converting to JSON..."
"$(dirname "$0")"/../../../tools/fs2json.py --zstd --out "$OUT_FSJSON" "$OUT_ROOTFS_TAR"

echo "Creating flat filesystem..."
# Clear old files to prevent conflicts
rm -rf "$OUT_ROOTFS_FLAT"
mkdir -p "$OUT_ROOTFS_FLAT"
"$(dirname "$0")"/../../../tools/copy-to-sha256.py --zstd "$OUT_ROOTFS_TAR" "$OUT_ROOTFS_FLAT"

echo "Done. Artifacts created at $IMAGES"