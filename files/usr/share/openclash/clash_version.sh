#!/bin/bash
. /usr/share/openclash/openclash_curl.sh

set_lock() {
   exec 884>"/tmp/lock/openclash_clash_version.lock" 2>/dev/null
   flock -x 884 2>/dev/null
}

del_lock() {
   flock -u 884 2>/dev/null
   rm -rf "/tmp/lock/openclash_clash_version.lock" 2>/dev/null
}

set_lock

RELEASE_BRANCH=$(uci -q get openclash.config.release_branch || echo "master")
github_address_mod=$(uci -q get openclash.config.github_address_mod || echo 0)
if [ -n "$1" ]; then
   github_address_mod="$1"
fi

# Hanya mengecek versi core yang terinstall tanpa download
CORE_TYPE=$(uci -q get openclash.config.core_type)
if [ -z "$CORE_TYPE" ]; then
   CORE_TYPE="TUN"
fi

case $CORE_TYPE in
   "TUN")
      CORE_FILE="/etc/openclash/core/clash"
      ;;
   "Meta")
      CORE_FILE="/etc/openclash/core/clash_meta"
      ;;
   "Game")
      CORE_FILE="/etc/openclash/core/clash_tun"
      ;;
   *)
      CORE_FILE="/etc/openclash/core/clash"
      ;;
esac

if [ -f "$CORE_FILE" ]; then
   CORE_VERSION=$($CORE_FILE -v 2>/dev/null | head -1 | awk '{print $2}' 2>/dev/null)
   echo "Current Clash Core ($CORE_TYPE) Version: $CORE_VERSION"
else
   echo "Clash Core ($CORE_TYPE) is not installed"
fi

del_lock