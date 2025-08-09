#!/bin/bash

# Source include file
. ./scripts/INCLUDE.sh

# Exit on error
set -e

# Display Profile
make info

# Validasi
PROFILE=""
PACKAGES=""
MISC=""
EXCLUDED=""

# Core system + Web Server + LuCI
PACKAGES+=" libc bash block-mount coreutils-base64 coreutils-sleep coreutils-stat coreutils-stty \
curl wget-ssl tar unzip parted losetup uhttpd uhttpd-mod-ubus \
luci-mod-admin-full luci-lib-ip luci-compat luci-ssl luci luci-base"

# USB + LAN Networking Drivers And Tethering Tools
PACKAGES+=" kmod-usb-net  kmod-mii  kmod-nls-utf8 kmod-usb2 kmod-usb3 \
kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-usb-net-rtl8152 usbutils"

# VPN Tunnel
OPENCLASH="coreutils-nohup bash ca-certificates ipset ip-full libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag kmod-nft-tproxy luci-app-openclash"
NIKKI="nikki luci-app-nikki"
NEKO="bash kmod-tun php8 php8-cgi luci-app-neko"
PASSWALL="chinadns-ng resolveip dns2socks dns2tcp ipt2socks microsocks tcping xray-core xray-plugin luci-app-passwall"

# Option Tunnel
add_tunnel_packages() {
    local option="$1"
    if [[ "$option" == "openclash" ]]; then
        PACKAGES+=" $OPENCLASH"
    elif [[ "$option" == "openclash-nikki" ]]; then
        PACKAGES+=" $OPENCLASH $NIKKI"
    elif [[ "$option" == "openclash-nikki-passwall" ]]; then
        PACKAGES+=" $OPENCLASH $NIKKI $PASSWALL"
    elif [[ "$option" == "" ]]; then
        # No tunnel packages
        :
    fi
}

# Storage - NAS
PACKAGES+=" luci-app-diskman kmod-usb-storage kmod-usb-storage-uas ntfs-3g"

# Theme + UI
PACKAGES+=" luci-theme-argon"

# PHP8
PACKAGES+=" php8 php8-fastcgi php8-fpm php8-mod-session php8-mod-ctype php8-mod-fileinfo php8-mod-zip php8-mod-iconv php8-mod-mbstring"

# Misc Packages + Custom Packages
MISC+=" zoneinfo-core zoneinfo-asia jq openssh-sftp-server zram-swap \
screen lolcat \
luci-app-poweroffdevice luci-app-ramfree luci-app-tinyfm luci-app-ttyd"

# Profil Name
configure_profile_packages() {
    local profile_name="$1"

    if [[ "$profile_name" == "rpi-4" ]]; then
        PACKAGES+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio"
    fi

    if [[ "${ARCH_2:-}" == "x86_64" ]] || [[ "${ARCH_2:-}" == "i386" ]]; then
        PACKAGES+=" kmod-iwlwifi iw-full pciutils wireless-tools"
    fi

    if [[ "${TYPE:-}" == "OPHUB" ]]; then
        PACKAGES+=" luci-app-amlogic btrfs-progs kmod-fs-btrfs"
        EXCLUDED+=" -procd-ujail"
    elif [[ "${TYPE:-}" == "ULO" ]]; then
        PACKAGES+=" luci-app-amlogic"
        EXCLUDED+=" -procd-ujail"
    fi
}

# Packages Base
configure_release_packages() {
    if [[ "${BASE:-}" == "openwrt" ]]; then
        MISC+=" luci-app-temp-status"
        EXCLUDED+=" -dnsmasq"
    elif [[ "${BASE:-}" == "immortalwrt" ]]; then
        MISC+=""
        EXCLUDED+=" -dnsmasq -cpusage -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        if [[ "${ARCH_2:-}" == "x86_64" ]] || [[ "${ARCH_3:-}" == "i386_pentium4" ]]; then
            EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
        fi
    fi
}

# Build Firmware
build_firmware() {
    local target_profile="$1"
    local tunnel_option="${2:-}"
    local build_files="files"

    log "INFO" "Starting build for profile '$target_profile' with tunnel option '$tunnel_option'..."

    configure_profile_packages "$target_profile"
    add_tunnel_packages "$tunnel_option"
    configure_release_packages

    # Add Misc Packages
    PACKAGES+=" $MISC"

    make image PROFILE="$target_profile" PACKAGES="$PACKAGES $EXCLUDED" FILES="$build_files"
    local build_status=$?

    if [ "$build_status" -eq 0 ]; then
        log "SUCCESS" "Build completed successfully!"
    else
        log "ERROR" "Build failed with exit code $build_status"
        exit "$build_status"
    fi
}

# Validasi Argumen
if [ -z "${1:-}" ]; then
    log "ERROR" "Profile not specified. Usage: $0 <profile> [tunnel_option]"
    exit 1
fi

# Running Build
build_firmware "$1" "${2:-}"
