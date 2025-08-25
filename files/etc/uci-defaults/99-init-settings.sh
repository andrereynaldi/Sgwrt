#!/bin/sh

# Setup logging
LOG_FILE="/root/setup.log"
exec > "$LOG_FILE" 2>&1

# logging dengan status
log_status() {
    local status="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$status" in
        "INFO")
            echo "[$timestamp] [INFO] $message"
            ;;
        "SUCCESS")
            echo "[$timestamp] [SUCCESS] ✓ $message"
            ;;
        "ERROR")
            echo "[$timestamp] [ERROR] ✗ $message"
            ;;
        "WARNING")
            echo "[$timestamp] [WARNING] ⚠ $message"
            ;;
        *)
            echo "[$timestamp] $message"
            ;;
    esac
}

# header log
log_status "INFO" "========================================="
log_status "INFO" "Setup Script Started"
log_status "INFO" "Script Setup"
log_status "INFO" "Installed Time: $(date '+%A, %d %B %Y %T')"
log_status "INFO" "========================================="

# change icon port
sed -i -E 's/icons\/port_%s\.(svg|png)/icons\/port_%s.gif/g' /www/luci-static/resources/view/status/include/29_ports.js 2>/dev/null
mv /www/luci-static/resources/view/status/include/29_ports.js /www/luci-static/resources/view/status/include/28_ports.js 2>/dev/null
log_status "SUCCESS" "Firmware and port modifications completed"

# check system release
log_status "INFO" "Checking system release..."
if grep -q "ImmortalWrt" /etc/openwrt_release 2>/dev/null; then
    log_status "INFO" "ImmortalWrt detected"
    sed -i 's/\(DISTRIB_DESCRIPTION='\''ImmortalWrt [0-9]*\.[0-9]*\.[0-9]*\).*'\''/\1'\''/g' /etc/openwrt_release 2>/dev/null
    sed -i 's|system/ttyd|services/ttyd|g' /usr/share/luci/menu.d/luci-app-ttyd.json 2>/dev/null
    BRANCH_VERSION=$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release 2>/dev/null | awk -F"'" '{print $2}')
    log_status "INFO" "Branch version: $BRANCH_VERSION"
elif grep -q "OpenWrt" /etc/openwrt_release 2>/dev/null; then
    log_status "INFO" "OpenWrt detected"
    sed -i 's/\(DISTRIB_DESCRIPTION='\''OpenWrt [0-9]*\.[0-9]*\.[0-9]*\).*'\''/\1'\''/g' /etc/openwrt_release 2>/dev/null
    mv /www/luci-static/resources/view/status/include/27_temperature.js /www/luci-static/resources/view/status/include/15_temperature.js 2>/dev/null
    BRANCH_VERSION=$(grep 'DISTRIB_DESCRIPTION=' /etc/openwrt_release 2>/dev/null | awk -F"'" '{print $2}')
    log_status "INFO" "Branch version: $BRANCH_VERSION"
else
    log_status "WARNING" "Unknown system release"
fi

log_status "INFO" "Setting up root password..."
(echo "123456879"; sleep 2; echo "123456879") | passwd >/dev/null 2>&1
log_status "SUCCESS" "Root password configured"

# disable opkg signature check
log_status "INFO" "Disabling OPKG signature check..."
sed -i 's/option check_signature/# option check_signature/g' /etc/opkg.conf 2>/dev/null
log_status "SUCCESS" "OPKG signature check disabled"

# add custom repository
log_status "INFO" "Adding custom repository..."
ARCH=$(grep "OPENWRT_ARCH" /etc/os-release 2>/dev/null | awk -F '"' '{print $2}')
if [ -n "$ARCH" ]; then
    echo "src/gz custom_packages https://dl.openwrt.ai/latest/packages/$ARCH/kiddin9" >> /etc/opkg/customfeeds.conf 2>/dev/null
    log_status "SUCCESS" "Custom repository added for architecture: $ARCH"
else
    log_status "WARNING" "Could not determine architecture for custom repository"
fi

# remove login password ttyd
log_status "INFO" "Configuring TTYD without login password..."
uci set ttyd.@ttyd[0].command='/bin/bash --login' 2>/dev/null
uci commit ttyd 2>/dev/null
log_status "SUCCESS" "TTYD configuration completed"

# symlink Tinyfm
log_status "INFO" "Creating TinyFM symlink..."
ln -sf / /www/tinyfm/rootfs 2>/dev/null
log_status "SUCCESS" "TinyFM rootfs symlink created"

# setup misc settings
log_status "INFO" "Setting up misc settings and permissions..."
chmod -R +x /sbin /usr/bin 2>/dev/null
log_status "SUCCESS" "Misc settings configured"

# add TTL
log_status "INFO" "Adding and running TTL script..."
if [ -f /root/indowrt.sh ]; then
    chmod +x /root/indowrt.sh 2>/dev/null
    /root/indowrt.sh
    log_status "SUCCESS" "TTL script executed"
else
    log_status "WARNING" "indowrt.sh not found, skipping TTL configuration"
fi

# konfigurasi uhttpd dan PHP8
log_status "INFO" "Configuring uhttpd and PHP8..."

# uhttpd configuration
uci set uhttpd.main.ubus_prefix='/ubus' 2>/dev/null
uci set uhttpd.main.interpreter='.php=/usr/bin/php-cgi' 2>/dev/null
uci set uhttpd.main.index_page='cgi-bin/luci' 2>/dev/null
uci add_list uhttpd.main.index_page='index.html' 2>/dev/null
uci add_list uhttpd.main.index_page='index.php' 2>/dev/null
uci commit uhttpd 2>/dev/null

# PHP configuration
if [ -f "/etc/php.ini" ]; then
    cp /etc/php.ini /etc/php.ini.bak 2>/dev/null
    sed -i 's|^memory_limit = .*|memory_limit = 128M|g' /etc/php.ini 2>/dev/null
    sed -i 's|^max_execution_time = .*|max_execution_time = 60|g' /etc/php.ini 2>/dev/null
    sed -i 's|^display_errors = .*|display_errors = Off|g' /etc/php.ini 2>/dev/null
    sed -i 's|^;*date\.timezone =.*|date.timezone = Asia/Jakarta|g' /etc/php.ini 2>/dev/null
    log_status "SUCCESS" "PHP settings configured"
else
    log_status "WARNING" "/etc/php.ini not found, skipping PHP configuration"
fi

if [ -d /usr/lib/php8 ]; then
    ln -sf /usr/lib/php8 2>/dev/null
fi

/etc/init.d/uhttpd restart >/dev/null 2>&1
log_status "SUCCESS" "uhttpd and PHP8 configuration completed"

log_status "SUCCESS" "All setup completed successfully"
rm -rf /etc/uci-defaults/$(basename "$0") 2>/dev/null

log_status "INFO" "========================================="
log_status "INFO" "Setup Script Finished"
log_status "INFO" "Check log file: $LOG_FILE"
log_status "INFO" "========================================="

sync
sleep 7
reboot

exit 0
