# Portland HOP Standby Emulator (for Init PROXMobil3 Transit Readers)

A custom **standby / idle emulator** for Init PROXMobil3 transit validators that recreates a **Portland, OR HOP–style experience** using framebuffer animation, barcode scans, and NFC taps.

This replaces the stock idle screen with a looping animation and provides visual + audio feedback when a card or barcode is presented.

> ⚠️ **This is an emulator / visual behavior mod only.**  
> It does **not** connect to TriMet systems or process real fares.

---

## ⚠️ VERY IMPORTANT WARNING

- **This project remounts the root filesystem (`/`) as read-write**
  - Required to install a persistent `systemd` service
  - Interrupting this process can **brick the device**
- This is **unsupported firmware modification**
- **Proceed entirely at your own risk**

If you don’t know how to recover the unit, **do not run this**.

---

## Hardware / Firmware Requirements

### Hardware
- Init Proxmobil3
- ProxDongl3 by [Kevin Wallace](https://kevin.wallace.seattle.wa.us/pm3/)
- 800×480 framebuffer display (`/dev/fb0`)
- Barcode scanner
- NFC reader

**Dongle image:**  
`http://cdn.jarynb.com/uploads/1769021243-IMG_8257.webp`

**Reader image:**  
`http://cdn.jarynb.com/uploads/1769021258-IMG_8258.webp`


## What This Does

- Installs a persistent **`standby.service`**
- Shows:
  - **Startup animation** (before NX initializes devices)
  - **Looping standby animation**
- Temporarily starts NX to:
  - Initialize barcode + NFC hardware
  - Create serial device links
- Stops NX and disables the PIC32 watchdog
- Triggers **hit animation + beep** on:
  - Barcode scan
  - NFC tap
- Prevents idle blank screen during normal operation

---

## Setup Instructions

1. Create a FAT32 formatted USB drives with the following files at it's root:
autorun.sh
starting.bgra
anim.bgra
hit.bgra
beep.u8.pcm
2. Insert USB into the Proxdongl3
3. Power on the device
4. Wait for installer to complete
