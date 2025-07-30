#!/bin/bash
. /usr/share/openclash/openclash_curl.sh

set_lock() {
   exec 869>"/tmp/lock/openclash_version.lock" 2>/dev/null
   flock -x 869 2>/dev/null
}

del_lock() {
   flock -u 869 2>/dev/null
   rm -rf "/tmp/lock/openclash_version.lock" 2>/dev/null
}

set_lock

RELEASE_BRANCH=$(uci -q get openclash.config.release_branch || echo "master")
if [ -x "/bin/opkg" ]; then
   OP_CV=$(rm -f /var/lock/opkg.lock && opkg status luci-app-openclash 2>/dev/null |grep 'Version' |awk -F 'Version: ' '{print $2}' |awk -F '.' '{print $2$3}' 2>/dev/null)
elif [ -x "/usr/bin/apk" ]; then
   OP_CV=$(apk list luci-app-openclash 2>/dev/null|grep 'installed' | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 |awk -F '.' '{print $2$3}' 2>/dev/null)
fi
github_address_mod=$(uci -q get openclash.config.github_address_mod || echo 0)
if [ -n "$1" ]; then
   github_address_mod="$1"
fi

# Hanya mengecek versi terinstall
echo "Installed OpenClash Version: $OP_CV"

del_lock