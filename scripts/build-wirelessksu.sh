#!/usr/bin/env bash
set -euo pipefail

LOCALVERSION="$1"
MODULE_VERSION="$2"
KERNEL_SRC="/tmp/kernel"
RTL_SRC="/tmp/rtl8188fu"
MODDIR="modules/WirelessKSU"

echo "=== Building WirelessKSU module ==="
echo "Localversion: -${LOCALVERSION}"

# Clone and configure rtl8188fu
git clone https://github.com/kelebek333/rtl8188fu "$RTL_SRC"
cd "$RTL_SRC"
sed -i 's/CONFIG_WIFI_MONITOR = n/CONFIG_WIFI_MONITOR = y/' Makefile
sed -i 's/CONFIG_PLATFORM_I386_PC = y/CONFIG_PLATFORM_I386_PC = n/' Makefile
sed -i 's/#define __PHYDM_FEATURES$/#define __PHYDM_FEATURES_H__/' hal/phydm/phydm_features.h

# Build
make -C "$KERNEL_SRC" \
  O=/tmp/out_gs \
  M="$(pwd)" \
  CONFIG_RTL8188FU=m \
  CONFIG_WIFI_MONITOR=y \
  ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  LLVM=1 \
  LLVM_IAS=1 \
  USER_EXTRA_CFLAGS="-DCONFIG_LITTLE_ENDIAN -DCONFIG_IOCTL_CFG80211 -DRTW_USE_CFG80211_STA_EVENT -w" \
  modules 2>&1

echo "=== Module vermagic ==="
strings rtl8188fu.ko | grep vermagic

# Collect in-kernel modules
mkdir -p /tmp/ko-modules
for mod in cfg80211 mac80211 rfkill; do
  find /tmp/out_gs -iname "${mod}.ko" -exec cp {} /tmp/ko-modules/ \; 2>/dev/null || true
done
echo "In-kernel modules:"
ls -la /tmp/ko-modules/ || echo "none"

# Package
cd "$OLDPWD"
mkdir -p "$MODDIR/lkm"
mkdir -p "$MODDIR/system/etc/firmware/rtlwifi"

cp "$RTL_SRC/rtl8188fu.ko" "$MODDIR/lkm/"
cp "$RTL_SRC/firmware/rtl8188fufw.bin" "$MODDIR/system/etc/firmware/rtlwifi/" 2>/dev/null || true

for ko in /tmp/ko-modules/*.ko; do
  [ -f "$ko" ] || continue
  cp "$ko" "$MODDIR/lkm/"
done

VERSION_CODE=$(echo "$MODULE_VERSION" | tr -d '.')
cat > "$MODDIR/module.prop" << PROPEOF
id=wirelessksu
name=WirelessKSU - RTL8188FU Monitor Mode
version=${MODULE_VERSION}
versionCode=${VERSION_CODE}
author=AbirHasanAHK
description=RTL8188FU WiFi driver with monitor mode for USB adapters
minApi=28
PROPEOF

cat > "$MODDIR/post-fs-data.sh" << 'POSTFSEOF'
#!/system/bin/sh
MODPATH=${0%/*}
LOGFILE=/data/local/tmp/wirelessksu.log
echo "=== WirelessKSU post-fs-data ===" > $LOGFILE
echo "Kernel: $(uname -r)" >> $LOGFILE
cp -f $MODPATH/system/etc/firmware/rtlwifi/rtl8188fufw.bin /vendor/firmware/rtlwifi/ 2>> $LOGFILE
cp -f $MODPATH/system/etc/firmware/rtlwifi/rtl8188fufw.bin /lib/firmware/rtlwifi/ 2>> $LOGFILE
for mod in r8188eu; do
    if lsmod | grep -q "$mod"; then
        echo "Removing conflicting module: $mod" >> $LOGFILE
        rmmod $mod 2>> $LOGFILE
    fi
done
if ! lsmod | grep -q rtl8188fu; then
    echo "Loading rtl8188fu..." >> $LOGFILE
    insmod $MODPATH/lkm/rtl8188fu.ko 2>> $LOGFILE
    echo "exit: $?" >> $LOGFILE
fi
echo "Modules:" >> $LOGFILE
lsmod | grep -E "rtl|r8188|cfg80211|mac80211" >> $LOGFILE 2>&1
POSTFSEOF
chmod 755 "$MODDIR/post-fs-data.sh"

cat > "$MODDIR/service.sh" << 'SVCEOF'
#!/system/bin/sh
MODPATH=${0%/*}
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 3; done
mkdir -p /vendor/firmware/rtlwifi
mkdir -p /lib/firmware/rtlwifi
cp -f $MODPATH/system/etc/firmware/rtlwifi/rtl8188fufw.bin /vendor/firmware/rtlwifi/ 2>/dev/null
cp -f $MODPATH/system/etc/firmware/rtlwifi/rtl8188fufw.bin /lib/firmware/rtlwifi/ 2>/dev/null
if ! lsmod | grep -q rtl8188fu; then
    insmod $MODPATH/lkm/rtl8188fu.ko 2>/dev/null
fi
for iface in /sys/class/net/wlan*; do
    [ -d "$iface" ] || continue
    ip link set $(basename "$iface") up 2>/dev/null
done
SVCEOF
chmod 755 "$MODDIR/service.sh"

echo "=== Module contents ==="
find "$MODDIR" -type f | sort

cd modules
zip -9 -r "$GITHUB_WORKSPACE/WirelessKSU.zip" WirelessKSU/
