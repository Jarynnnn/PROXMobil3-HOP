# trimet hop standby emulator  
*(for init proxmobil3 transit card readers)*

this is a **standby / idle screen emulator** for init proxmobil3 transit validators that recreates a **portland hop–style look and feel**.

it replaces the stock idle behavior with framebuffer animations and gives visual + audio feedback when a card or barcode is scanned.

> ⚠️ **this is purely an emulator / visual behavior mod**  
> it does **not** connect to trimet, hop, or any real fare systems.

---

## important warning (please read)

- this project **remounts the root filesystem (`/`) as read-write**
  - required to install a persistent `systemd` service
  - interrupting this process **can brick the device**
- this is **unsupported firmware modification**
- you are doing this **entirely at your own risk**

if you don’t know how to recover one of these units, **don’t run this**.

---

## how to get it (important)

👉 **do not clone this repo and run it directly**

to actually use the emulator, **download the latest release** from the  
**GitHub Releases tab**.

the release archive includes **all required files** and is what you should put on the usb drive.

this repository itself only exists to host the installer script source.

---

## hardware / firmware requirements

### hardware
- init proxmobil3 validator
- proxdongl3 by [kevin wallace](https://kevin.wallace.seattle.wa.us/pm3/)
- 800×480 framebuffer display (`/dev/fb0`)
- barcode scanner
- nfc reader

![ProxDongl3 dongle](http://cdn.jarynb.com/uploads/1769021243-IMG_8257.webp)

![Init Proxmobil3 reader](http://cdn.jarynb.com/uploads/1769021258-IMG_8258.webp)

---

## what this repo includes (important)

**this repository only includes:**
- `autorun.sh` — the installer / setup script

**it does NOT include:**
- `starting.bgra`
- `anim.bgra`
- `hit.bgra`
- `beep.u8.pcm`
- the generated `standby.sh`

those files are **intentionally excluded** due to size constraints.

 **the GitHub release includes all required files**  
so you do not need to source or build them yourself.

the raw assets may be published here at a later date.  
if you’d like access sooner, feel free to **reach out to me directly**.

---

## what the script does

- installs a persistent `standby.service`
- shows:
  - a **startup animation** before nx initializes hardware
  - a **looping standby animation** during idle
- temporarily starts nx to:
  - initialize barcode + nfc hardware
  - create required serial device links
- stops nx and disables the pic32 watchdog
- triggers **hit animation + beep** on:
  - barcode scans
  - nfc taps
- prevents the display from going blank during idle operation

---

## setup instructions

1. download the latest release from the **releases tab**
2. format a usb drive as **fat32**
3. copy the release contents to the **root of the usb**:
   - `autorun.sh`
   - `starting.bgra`
   - `anim.bgra`
   - `hit.bgra`
   - `beep.u8.pcm`
4. insert the usb into the proxdongl3
5. power on the device
6. wait for the installer to complete

logs will be written to:
- `/tmp/autorun.log`
- `/tmp/standby.log`

---

## final notes

this is a fun reverse-engineering / preservation project meant to keep old transit hardware interesting and usable.

it is **not affiliated with trimet, hop, or init** in any way.
