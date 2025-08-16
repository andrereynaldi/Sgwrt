#!/bin/bash
#========================================================================================
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the make OpenWrt for Amlogic, Rockchip and Allwinner
# https://github.com/ophub/amlogic-s9xxx-openwrt
#
# Function: Customize the startup script, adding content as needed.
# Dependent script: /etc/rc.local
# File path: /etc/custom_service/start_service.sh
#
#========================================================================================
# Custom Service Log
custom_log="/tmp/start_service.log"

# Add custom log
echo "[$(date +"%Y.%m.%d.%H:%M:%S")] Start the custom service..." >${custom_log}

# Add network performance optimization
[[ -x "/usr/sbin/balethirq.pl" ]] && {
    perl /usr/sbin/balethirq.pl 2>/dev/null &&
        echo "[$(date +"%Y.%m.%d.%H:%M:%S")] The network optimization service started successfully." >>${custom_log}
fi

# Led display control
openvfd_enable="no"
openvfd_boxid="15"
if [[ "${openvfd_enable}" == "yes" && -n "${openvfd_boxid}" && -x "/usr/sbin/openwrt-openvfd" ]]; then
    (openwrt-openvfd "${openvfd_boxid}") || true
    log_message "OpenVFD service execution attempted." >>${custom_log}     
        
}

# Add custom log
echo "[$(date +"%Y.%m.%d.%H:%M:%S")] All custom services executed successfully!" >>${custom_log}
