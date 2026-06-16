#!/usr/bin/env python3
# Amlogic S805/meson8b BootROM USB recovery: serve the signed bootloader to the
# BL2 via the AMLC staged protocol -> BL2 inits DDR + runs u-boot.
# Usage: sudo .venv/bin/python recover.py bootloader.bin
import sys, time
from pyamlboot import pyamlboot

bl = open(sys.argv[1], 'rb').read()
dev = pyamlboot.AmlogicSoC()
print("bootloader bytes:", len(bl))

seq = 0
try:
    while True:
        (length, offset) = dev.getBootAMLC()
        print(f"seq={seq} AMLC request offset={offset:#x} length={length}")
        data = bl[offset:offset+length]
        if len(data) < length:
            data = data + b'\x00' * (length - len(data))
        dev.writeAMLCData(seq, offset, data)
        seq += 1
        if seq > 128:
            print("safety stop after 128 chunks"); break
except Exception as e:
    print("AMLC loop ended (BL2 likely running now):", repr(e))
print("done; watch UART for u-boot")
