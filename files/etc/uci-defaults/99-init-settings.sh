#!/bin/sh

# Setup logging
LOG_FILE="/root/setup-xidzswrt.log"
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
log_status "INFO" "XIDZs-WRT Setup Script Started"
log_status "INFO" "Script Setup By Xidz-x | Fidz"
log_status "INFO" "Installed Time: $(date '+%A, %d %B %Y %T')"
log_status "INFO" "========================================="

# modify firmware display
log_status "INFO" "Modifying firmware display..."
if sed -i "s#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' / ':'')+(luciversion||''),#_('Firmware Version'),(L.isObject(boardinfo.release)?boardinfo.release.description+' By Xidz_x':''),#g" /www/luci-static/resources/view/status/include/10_system.js 2>/dev/null; then
    log_status "SUCCESS" "Firmware display modified"
else
    log_status "ERROR" "Failed to modify firmware display"
fi

# change icon port
log_status "INFO" "Changing port icons..."
if sed -i -E 's/icons\/port_%s\.(svg|png)/icons\/port_%s.gif/g' /www/luci-static/resources/view/status/include/29_ports.js 2>/dev/null; then
    log_status "SUCCESS" "Port icons format changed"
else
    log_status "WARNING" "Port icons change failed or file not found"
fi

if mv /www/luci-static/resources/view/status/include/29_ports.js /www/luci-static/resources/view/status/include/11_ports.js 2>/dev/null; then
    log_status "SUCCESS" "Ports.js file moved and renamed"
else
    log_status "WARNING" "Ports.js move failed or file not found"
fi

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

# setup login root password
log_status "INFO" "Setting up root password..."
if (echo "xyyraa"; sleep 2; echo "xyyraa") | passwd >/dev/null 2>&1; then
    log_status "SUCCESS" "Root password configured"
else
    log_status "ERROR" "Failed to set root password"
fi

# setup hostname and timezone
log_status "INFO" "Configuring hostname and timezone to Asia/Jakarta..."
uci set system.@system[0].hostname='XIDZs-WRT' 2>/dev/null
uci set system.@system[0].timezone='WIB-7' 2>/dev/null
uci set system.@system[0].zonename='Asia/Jakarta' 2>/dev/null
uci delete system.ntp.server 2>/dev/null
uci add_list system.ntp.server='pool.ntp.org' 2>/dev/null
uci add_list system.ntp.server='id.pool.ntp.org' 2>/dev/null
uci add_list system.ntp.server='time.google.com' 2>/dev/null
uci commit system 2>/dev/null
log_status "SUCCESS" "System configuration completed"

# setup bahasa default
log_status "INFO" "Setting up default language to English..."
uci set luci.@core[0].lang='en' 2>/dev/null
uci commit luci 2>/dev/null
log_status "SUCCESS" "Language set to English"

# configure wan and lan
log_status "INFO" "Configuring WAN and LAN interfaces..."
uci set network.tethering=interface 2>/dev/null
uci set network.tethering.proto='dhcp' 2>/dev/null
uci set network.tethering.device='usb0' 2>/dev/null
uci set network.modem=interface 2>/dev/null
uci set network.modem.proto='dhcp' 2>/dev/null
uci set network.modem.device='eth1' 2>/dev/null
uci set network.mm=interface 2>/dev/null
uci set network.mm.proto='modemmanager' 2>/dev/null
uci set network.mm.device='/sys/devices/platform/scb/fd500000.pcie/pci0000:00/0000:00:00.0/0000:01:00.0/usb2/2-1' 2>/dev/null
uci set network.mm.apn='internet' 2>/dev/null
uci set network.mm.auth='none' 2>/dev/null
uci set network.mm.iptype='ipv4' 2>/dev/null
uci delete network.wan6 2>/dev/null
uci commit network 2>/dev/null
log_status "SUCCESS" "Network configuration completed"

log_status "INFO" "Configuring firewall..."
uci set firewall.@zone[1].network='tethering modem mm' 2>/dev/null
uci commit firewall 2>/dev/null
log_status "SUCCESS" "Firewall configuration completed"

# disable ipv6 lan
log_status "INFO" "Disabling IPv6 on LAN..."
uci delete dhcp.lan.dhcpv6 2>/dev/null
uci delete dhcp.lan.ra 2>/dev/null
uci delete dhcp.lan.ndp 2>/dev/null
uci commit dhcp 2>/dev/null
log_status "SUCCESS" "IPv6 disabled on LAN"

# configure wireless device
log_status "INFO" "Configuring wireless devices..."
uci set wireless.@wifi-device[0].disabled='0' 2>/dev/null
uci set wireless.@wifi-iface[0].disabled='0' 2>/dev/null
uci set wireless.@wifi-iface[0].mode='ap' 2>/dev/null
uci set wireless.@wifi-iface[0].encryption='psk2' 2>/dev/null
uci set wireless.@wifi-iface[0].key='XIDZs2025' 2>/dev/null
uci set wireless.@wifi-device[0].country='ID' 2>/dev/null

# check for Raspberry Pi Devices
if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
    log_status "INFO" "Raspberry Pi 3/4 detected, configuring 5GHz WiFi..."
    uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT_5G' 2>/dev/null
    uci set wireless.@wifi-device[0].channel='149' 2>/dev/null
    uci set wireless.@wifi-device[0].htmode='VHT80' 2>/dev/null
else
    uci set wireless.@wifi-iface[0].ssid='XIDZs-WRT' 2>/dev/null
    uci set wireless.@wifi-device[0].channel='1' 2>/dev/null
    uci set wireless.@wifi-device[0].htmode='HT20' 2>/dev/null
    log_status "INFO" "Standard WiFi configuration applied"
fi

uci commit wireless 2>/dev/null
wifi reload >/dev/null 2>&1
wifi up >/dev/null 2>&1
log_status "SUCCESS" "Wireless configuration completed"

# check wireless interface
if iw dev 2>/dev/null | grep -q Interface; then
    log_status "SUCCESS" "Wireless interface detected"
    if grep -q "Raspberry Pi 4\|Raspberry Pi 3" /proc/cpuinfo 2>/dev/null; then
        if ! grep -q "wifi up" /etc/rc.local 2>/dev/null; then
            sed -i '/exit 0/i # remove if you dont use wireless' /etc/rc.local 2>/dev/null
            sed -i '/exit 0/i sleep 10 && wifi up' /etc/rc.local 2>/dev/null
        fi
        if ! grep -q "wifi up" /etc/crontabs/root 2>/dev/null; then
            echo "# remove if you dont use wireless" >> /etc/crontabs/root 2>/dev/null
            echo "0 */12 * * * wifi down && sleep 5 && wifi up" >> /etc/crontabs/root 2>/dev/null
            /etc/init.d/cron restart >/dev/null 2>&1
        fi
    fi
else
    log_status "WARNING" "No wireless device detected"
fi

# remove huawei me909s and dw5821e usb-modeswitch
log_status "INFO" "Removing Huawei ME909S and DW5821E USB modeswitch entries..."
sed -i -e '/12d1:15c1/,+5d' -e '/413c:81d7/,+5d' /etc/usb-mode.json 2>/dev/null
log_status "SUCCESS" "USB modeswitch entries removed"

# disable xmm-modem
log_status "INFO" "Disabling XMM-Modem using UCI"
uci set xmm-modem.@xmm-modem[0].enable='0' 2>/dev/null
uci commit xmm-modem 2>/dev/null
log_status "SUCCESS" "XMM-Modem disabled"

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

# setup default theme
log_status "INFO" "Setting up Argon theme as default..."
uci set luci.main.mediaurlbase='/luci-static/argon' 2>/dev/null
uci commit luci 2>/dev/null
log_status "SUCCESS" "Argon theme set as default"

# remove login password ttyd
log_status "INFO" "Configuring TTYD without login password..."
uci set ttyd.@ttyd[0].command='/bin/bash --login' 2>/dev/null
uci commit ttyd 2>/dev/null
log_status "SUCCESS" "TTYD configuration completed"

# symlink Tinyfm
log_status "INFO" "Creating TinyFM symlink..."
ln -sf / /www/tinyfm/rootfs 2>/dev/null
log_status "SUCCESS" "TinyFM rootfs symlink created"

# setup device amlogic
log_status "INFO" "Checking for Amlogic device configuration..."
if opkg list-installed 2>/dev/null | grep -q luci-app-amlogic; then
    log_status "INFO" "luci-app-amlogic detected"
    rm -f /etc/profile.d/30-sysinfo.sh 2>/dev/null
    sed -i '/exit 0/i #sleep 5 && /usr/bin/k5hgled -r' /etc/rc.local 2>/dev/null
    sed -i '/exit 0/i #sleep 5 && /usr/bin/k6hgled -r' /etc/rc.local 2>/dev/null
else
    log_status "INFO" "luci-app-amlogic not detected"
    rm -f /usr/bin/k5hgled /usr/bin/k6hgled /usr/bin/k5hgledon /usr/bin/k6hgledon 2>/dev/null
fi

# setup misc settings
log_status "INFO" "Setting up misc settings and permissions..."
sed -i -e 's/\[ -f \/etc\/banner \] && cat \/etc\/banner/#&/' -e 's/\[ -n \"\$FAILSAFE\" \] && cat \/etc\/banner.failsafe/& || \/usr\/bin\/foundx/' /etc/profile 2>/dev/null
chmod -R +x /sbin /usr/bin 2>/dev/null
chmod +x /etc/init.d/vnstat_backup 2>/dev/null
chmod +x /etc/init.d/issue 2>/dev/null
chmod +x /usr/lib/ModemManager/connection.d/10-report-down 2>/dev/null
chmod +x /www/cgi-bin/reset-vnstat.sh /www/vnstati/vnstati.sh 2>/dev/null
chmod 600 /etc/vnstat.conf 2>/dev/null

if [ -f /root/install2.sh ]; then
    chmod +x /root/install2.sh 2>/dev/null
    /root/install2.sh
    log_status "SUCCESS" "install2 script executed"
else
    log_status "INFO" "install2.sh not found, skipping"
fi
log_status "SUCCESS" "Misc settings configured"

# add auto sinkron jam, Clean Cache, Remove mm tty
log_status "INFO" "Add Auto Sinkron Jam, Clean Cache, Remove mm tty..."
sed -i '/exit 0/i #sh /usr/bin/autojam.sh bug.com' /etc/rc.local 2>/dev/null
sed -i '/exit 0/i #/sbin/free.sh' /etc/rc.local 2>/dev/null
rm -f /etc/hotplug.d/tty/25-modemmanager-tty 2>/dev/null
log_status "SUCCESS" "Auto sync, Cache clean, Remove mm tty applied"

# add rules
log_status "INFO" "Adding and running rules script..."
if [ -f /root/rules.sh ]; then
    chmod +x /root/rules.sh 2>/dev/null
    /root/rules.sh
    log_status "SUCCESS" "Rules script executed"
else
    log_status "WARNING" "rules.sh not found, skipping Rules configuration"
fi

# move_safe
log_status "INFO" "Move safe configuration..."
if [ -f /root/move_safe.sh ]; then
    chmod +x /root/move_safe.sh 2>/dev/null
    /root/move_safe.sh
    log_status "SUCCESS" "move_safe configuration script executed"
else
    log_status "WARNING" "move_safe.sh not found, skipping move_safe configuration"
fi

# mv_safe
log_status "INFO" "Mv safe configuration..."
if [ -f /root/mv_safe.sh ]; then
    chmod +x /root/mv_safe.sh 2>/dev/null
    /root/mv_safe.sh
    log_status "SUCCESS" "mv_safe configuration script executed"
else
    log_status "WARNING" "mv_safe.sh not found, skipping mv_safe configuration"
fi

# nikki-x
log_status "INFO" "Adding and running Nikki-x script..."
if [ -f /root/nikki-x.sh ]; then
    chmod +x /root/nikki-x.sh 2>/dev/null
    /root/nikki-x.sh
    log_status "SUCCESS" "Nikki-x script executed"
else
    log_status "WARNING" "Nikki-x.sh not found, skipping Nikki configuration"
fi

# add TTL
log_status "INFO" "Adding and running TTL script..."
if [ -f /root/indowrt.sh ]; then
    chmod +x /root/indowrt.sh 2>/dev/null
    /root/indowrt.sh
    log_status "SUCCESS" "TTL script executed"
else
    log_status "WARNING" "indowrt.sh not found, skipping TTL configuration"
fi

# add port
log_status "INFO" "Adding port configuration..."
if [ -f /root/addport.sh ]; then
    chmod +x /root/addport.sh 2>/dev/null
    /root/addport.sh
    log_status "SUCCESS" "Port configuration script executed"
else
    log_status "WARNING" "addport.sh not found, skipping port configuration"
fi

# move jquery.min.js
log_status "INFO" "Moving jQuery library..."
mv /usr/share/netdata/web/lib/jquery-3.6.0.min.js /usr/share/netdata/web/lib/jquery-2.2.4.min.js 2>/dev/null
log_status "SUCCESS" "jQuery library version changed"

# create directory vnstat
log_status "INFO" "Creating VnStat directory..."
mkdir -p /etc/vnstat 2>/dev/null
log_status "SUCCESS" "VnStat directory created"

# restart netdata and vnstat
log_status "INFO" "Restarting Netdata and VnStat services..."
/etc/init.d/netdata restart >/dev/null 2>&1
/etc/init.d/vnstat restart >/dev/null 2>&1
log_status "SUCCESS" "Services restarted"

# run vnstati.sh
log_status "INFO" "Running VnStati script..."
/www/vnstati/vnstati.sh >/dev/null 2>&1
log_status "SUCCESS" "VnStati script executed"

# setup enable services
log_status "INFO" "Enable Services.."
/etc/init.d/vnstat_backup enable >/dev/null 2>&1
/etc/init.d/issue enable >/dev/null 2>&1
log_status "SUCCESS" "Services enabled"

# setup tunnel installed
log_status "INFO" "Checking for tunnel applications..."
for pkg in luci-app-openclash luci-app-nikki luci-app-passwall; do
    if opkg list-installed 2>/dev/null | grep -qw "$pkg"; then
        log_status "INFO" "$pkg detected"
        case "$pkg" in
            luci-app-openclash)
                chmod +x /etc/openclash/core/clash_meta 2>/dev/null
                chmod +x /etc/openclash/Country.mmdb 2>/dev/null
                chmod +x /etc/openclash/Geo* 2>/dev/null
                
                log_status "INFO" "Patching OpenClash overview..."
                if [ -f /usr/bin/ocpatch.sh ]; then
                    bash /usr/bin/ocpatch.sh >/dev/null 2>&1
                    log_status "SUCCESS" "OpenClash overview patched"
                else
                    log_status "WARNING" "ocpatch.sh not found"
                fi
                
                ln -sf /etc/openclash/history/quenx.db /etc/openclash/cache.db 2>/dev/null
                ln -sf /etc/openclash/core/clash_meta /etc/openclash/clash 2>/dev/null
                rm -f /etc/config/openclash 2>/dev/null
                rm -rf /etc/openclash/custom /etc/openclash/game_rules 2>/dev/null
                find /etc/openclash/rule_provider -type f ! -name '*.yaml' -exec rm -f {} \; 2>/dev/null
                mv /etc/config/openclash1 /etc/config/openclash 2>/dev/null
                ;;
            luci-app-nikki)
                rm -rf /etc/nikki/run/providers 2>/dev/null
                chmod +x /etc/nikki/run/Geo* 2>/dev/null
                log_status "INFO" "Creating symlinks from OpenClash to Nikki..."
                ln -sf /etc/openclash/proxy_provider /etc/nikki/run 2>/dev/null
                ln -sf /etc/openclash/rule_provider /etc/nikki/run 2>/dev/null
                sed -i '64s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '170s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
            luci-app-passwall)
                sed -i '88s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '171s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
        esac
    else
        log_status "INFO" "$pkg not detected, cleaning up..."
        case "$pkg" in
            luci-app-openclash)
                rm -f /etc/config/openclash1 2>/dev/null
                rm -rf /etc/openclash 2>/dev/null
                sed -i '104s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '167s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                sed -i '187s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                sed -i '188s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
            luci-app-nikki)
                rm -rf /etc/config/nikki /etc/nikki 2>/dev/null
                sed -i '120s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '168s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
            luci-app-passwall)
                rm -f /etc/config/passwall 2>/dev/null
                sed -i '136s/Enable/Disable/' /etc/config/alpha 2>/dev/null
                sed -i '169s#.*#<!-- & -->#' /usr/lib/lua/luci/view/themes/argon/header.htm 2>/dev/null
                ;;
        esac
    fi
done
log_status "SUCCESS" "Tunnel applications configured"

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
log_status "INFO" "XIDZs-WRT Setup Script Finished"
log_status "INFO" "Check log file: $LOG_FILE"
log_status "INFO" "========================================="

sync
sleep 5
reboot

exit 0
