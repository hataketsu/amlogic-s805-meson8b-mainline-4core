#!/bin/sh
/bin/busybox --install -s /bin
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts; mount -t devpts devpts /dev/pts 2>/dev/null
echo
echo "=== Amlogic S805 / meson8b - mainline 6.20 - 4 core - HDMI 1080p ==="
echo "    Type here with a USB keyboard. (serial shell also on UART)"
echo
# interactive shell on the HDMI virtual terminal (tty1) for the USB keyboard
( while true; do
    setsid -c /bin/sh -c 'exec /bin/sh </dev/tty1 >/dev/tty1 2>&1' 2>/dev/null \
      || /bin/sh </dev/tty1 >/dev/tty1 2>&1
    sleep 1
  done ) &
# keep a shell on the serial console too
exec /bin/sh
