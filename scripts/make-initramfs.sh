#!/usr/bin/env bash
# Build a minimal busybox initramfs that loads the SD-card MMC + ext4 + crc32c modules and
# switch_roots to the ext4 filesystem labelled ARMROOT. Output: ./uInitrd
set -euo pipefail
KVER=${KVER:-6.1.174}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODS="$HERE/modout/lib/modules/$KVER"
BB=${BUSYBOX:-$(command -v busybox)}   # a STATIC armhf busybox; or extract from busybox-static .deb
[ -d "$MODS" ] || { echo "build the kernel first ($MODS missing)"; exit 1; }

rm -rf ir; mkdir -p ir/{bin,dev,proc,sys,mnt,lib/modules/$KVER/kernel/{drivers/mmc/host,fs/ext4,fs/jbd2,crypto,lib}}
cp "$BB" ir/bin/busybox; ln -s busybox ir/bin/sh; ln -s busybox ir/bin/mount
for m in drivers/mmc/host/meson-mx-sdio fs/ext4/ext4 fs/jbd2/jbd2 fs/mbcache lib/crc16 \
         lib/libcrc32c crypto/crc32c_generic; do
  cp "$MODS/kernel/$m.ko" "ir/lib/modules/$KVER/kernel/$m.ko"
done
depmod -b ir "$KVER"
cat > ir/init <<'EOF'
#!/bin/sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
modprobe meson-mx-sdio; modprobe crc32c_generic; modprobe libcrc32c; modprobe ext4
for i in $(seq 1 25); do ROOT=$(findfs LABEL=ARMROOT 2>/dev/null); [ -b "$ROOT" ] && break; sleep 1; done
[ -b "$ROOT" ] || { echo "ARMROOT not found"; exec /bin/sh; }
mount -o rw "$ROOT" /mnt
exec switch_root /mnt /sbin/init
EOF
chmod +x ir/init
sudo mknod ir/dev/console c 5 1; sudo mknod ir/dev/null c 1 3
( cd ir && sudo find . | sudo cpio -o -H newc 2>/dev/null | gzip ) > initramfs.cpio.gz
mkimage -A arm -O linux -T ramdisk -C gzip -n initrd -d initramfs.cpio.gz "$HERE/uInitrd"
echo "done: $HERE/uInitrd"
