FROM i386/debian:stretch-slim

WORKDIR /root/build
ENV DEBIAN_FRONTEND=noninteractive

# 1. Base Setup (Point to the Debian Archive for Legacy Stretch)
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until && \
    rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://archive.debian.org/debian/ stretch main contrib non-free" > /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y --allow-downgrades --no-install-recommends \
    linux-image-686 \
    libsystemd0=232-25+deb9u12 \
    libudev1=232-25+deb9u12 \
    systemd \
    systemd-sysv \
    locales \
    libterm-readline-perl-perl \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure Locales & Shell
RUN echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    locale-gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    chsh -s /bin/bash root  

# 3. Install Minimal X11, Input Drivers, Fonts, UI Libraries, and Python 2/WX dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    xserver-xorg-core xserver-xorg-video-fbdev xinit fluxbox \
    xserver-xorg-input-mouse xserver-xorg-input-kbd xserver-xorg-input-evdev \
    libxext6 libxrender1 libxtst6 libxi6 libx11-xcb1 libxrender-dev \
    libfontconfig1 fonts-dejavu-core \
    wget tar ca-certificates xterm \
    python python-wxgtk3.0 \
    && rm -rf /var/lib/apt/lists/*

# 4. Install Prover9-Mace4 (p9m4) GUI
COPY p9m4-v05.tar.gz /tmp/p9m4.tar.gz
RUN mkdir -p /opt && \
    tar -xzf /tmp/p9m4.tar.gz -C /opt && \
    rm /tmp/p9m4.tar.gz

RUN passwd -d root && \
    sed -i 's/nullok_secure/nullok/' /etc/pam.d/common-auth

# 6. Configure Serial Console
COPY getty-noclear.conf getty-override.conf /etc/systemd/system/getty@tty1.service.d/
COPY getty-autologin-serial.conf /etc/systemd/system/serial-getty@ttyS0.service.d/

RUN systemctl enable serial-getty@ttyS0.service

# 7. Disable Unnecessary Services
RUN systemctl disable systemd-timesyncd.service && \
    systemctl disable apt-daily.timer && \
    systemctl disable apt-daily-upgrade.timer

# ------------------------------------------------------------------------------
# 8. 9p Filesystem Boot Configuration
# ------------------------------------------------------------------------------
RUN printf '%s\n' 9p 9pnet 9pnet_virtio virtio virtio_ring virtio_pci | tee -a /etc/initramfs-tools/modules

RUN echo '#!/bin/sh' > /etc/initramfs-tools/scripts/boot-9p && \
    echo 'case $1 in prereqs) exit 0;; esac' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo '. /scripts/functions' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mkdir -p ${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    echo 'mount -n -t 9p -o trans=virtio,version=9p2000.L,cache=loose,rw host9p ${rootmnt}' >> /etc/initramfs-tools/scripts/boot-9p && \
    chmod +x /etc/initramfs-tools/scripts/boot-9p

RUN echo 'BOOT=boot-9p' | tee -a /etc/initramfs-tools/initramfs.conf
RUN update-initramfs -u

# 9. Configure X11 and Auto-start
# Modified to execute with classic Python 2
RUN echo 'cd /opt/p9m4-v05 && python prover9-mace4.py & \n\
(sleep 5 && echo -e "\n\nGUI_READY\n" > /dev/ttyS0) & \n\
exec fluxbox' > /root/.xinitrc

RUN { \
    echo 'if [ -z "$DISPLAY" ]; then'; \
    echo '  echo "127.0.0.1 localhost" > /etc/hosts'; \
    echo '  echo "localhost" > /etc/hostname'; \
    echo '  hostname localhost'; \
    echo '  startx -- -ac'; \
    echo 'fi'; \
} >> /root/.bashrc

# 10. Force Xorg to use the FBDEV driver
RUN mkdir -p /etc/X11/xorg.conf.d && \
    echo 'Section "Device"\n\
    Identifier "Card0"\n\
    Driver "fbdev"\n\
EndSection' > /etc/X11/xorg.conf.d/10-fbdev.conf

WORKDIR /root