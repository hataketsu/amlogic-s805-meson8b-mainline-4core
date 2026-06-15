#!/usr/bin/env bash
# Download mainline Linux 6.1.174, apply the meson8b-smp-tz patch, cross-build for armhf.
# Produces: arch/arm/boot/zImage + /srv/tftp/uImage + stripped modules in ./modout
set -euo pipefail
KVER=6.1.174
CROSS=arm-linux-gnueabihf-
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# deps (Debian/Ubuntu host): crossbuild-essential-armhf bc bison flex libssl-dev libelf-dev u-boot-tools
command -v ${CROSS}gcc >/dev/null || { echo "install crossbuild-essential-armhf"; exit 1; }

[ -d linux-$KVER ] || {
  curl -fLO "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
  tar xf linux-$KVER.tar.xz
}
cd linux-$KVER
patch -p1 -N < "$HERE/kernel/0001-meson8b-smp-tz-secure-monitor.patch" || true

# config: start from a Debian armmp config if you have one, else multi_v7 + meson
if [ ! -f .config ]; then
  make ARCH=arm multi_v7_defconfig
  ./scripts/config -e ARCH_MESON -e MACH_MESON8B -e SERIAL_MESON -e SERIAL_MESON_CONSOLE \
                   -e COMMON_CLK_MESON8B -e PINCTRL_MESON8B -e SMP \
                   -m MMC_MESON_MX_SDIO -m STMMAC_ETH -m DWMAC_MESON
  make ARCH=arm olddefconfig
fi

make ARCH=arm CROSS_COMPILE=$CROSS -j"$(nproc)" zImage modules
mkimage -A arm -O linux -T kernel -C none -a 0x1080000 -e 0x1080000 -n meson8b \
        -d arch/arm/boot/zImage "$HERE/uImage"
rm -rf "$HERE/modout"
make ARCH=arm CROSS_COMPILE=$CROSS INSTALL_MOD_PATH="$HERE/modout" INSTALL_MOD_STRIP=1 modules_install
echo "done: $HERE/uImage + $HERE/modout/lib/modules/$KVER"
