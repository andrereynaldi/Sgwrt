#!/bin/bash
. /usr/share/openclash/log.sh
. /usr/share/openclash/openclash_curl.sh

set_lock() {
   exec 878>"/tmp/lock/openclash_update.lock" 2>/dev/null
   flock -x 878 2>/dev/null
}

del_lock() {
   flock -u 878 2>/dev/null
   rm -rf "/tmp/lock/openclash_update.lock" 2>/dev/null
}

set_lock

# Hanya mengecek versi yang terinstall tanpa mengecek update
if [ -x "/bin/opkg" ]; then
   OP_CV=$(rm -f /var/lock/opkg.lock && opkg status luci-app-openclash 2>/dev/null |grep 'Version' |awk -F 'Version: ' '{print $2}' 2>/dev/null)
elif [ -x "/usr/bin/apk" ]; then
   OP_CV=$(apk list luci-app-openclash 2>/dev/null|grep 'installed' | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 2>/dev/null)
fi

RELEASE_BRANCH=$(uci -q get openclash.config.release_branch || echo "master")
github_address_mod=$(uci -q get openclash.config.github_address_mod || echo 0)

#一键更新
if [ "$1" = "one_key_update" ]; then
   uci -q set openclash.config.enable=1
   uci -q commit openclash
   if [ "$github_address_mod" = "0" ] && [ -z "$2" ]; then
      LOG_OUT "Tip: If the download fails, try setting the CDN in Overwrite Settings - General Settings - Github Address Modify Options"
   fi
   if [ -n "$2" ]; then
      /usr/share/openclash/openclash_core.sh "Meta" "$1" "$2" >/dev/null 2>&1 &
      github_address_mod="$2"
   else
      /usr/share/openclash/openclash_core.sh "Meta" "$1" >/dev/null 2>&1 &
   fi
   
   wait
else
   if [ "$github_address_mod" = "0" ]; then
      LOG_OUT "Tip: If the download fails, try setting the CDN in Overwrite Settings - General Settings - Github Address Modify Options"
   fi
fi

# Hanya menampilkan versi yang terinstall tanpa melakukan update
if [ -n "$OP_CV" ]; then
   LOG_OUT "Current OpenClash Version: $OP_CV - No update check performed"
else
   LOG_OUT "OpenClash is not installed or version cannot be detected"
fi

# Restart jika diperlukan
if [ "$(uci -q get openclash.config.restart)" -eq 1 ]; then
   uci -q set openclash.config.restart=0
   uci -q commit openclash
   /etc/init.d/openclash restart >/dev/null 2>&1 &
else
   SLOG_CLEAN
fi

del_lock