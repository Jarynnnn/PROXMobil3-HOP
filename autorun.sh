#!/bin/sh
set -eu

# ===================== config =====================
# Mount USB somewhere always-writable (even if / is still RO)
USB_MNT="/tmp/usb"

# Files expected on USB
ANIM_USB="$USB_MNT/anim.bgra"
START_USB="$USB_MNT/starting.bgra"
HIT_USB="$USB_MNT/hit.bgra"
BEEP_USB="$USB_MNT/beep.u8.pcm"

# Install location (persistent)
INSTALL_DIR="/init/efad/mp_sd/standby"
STANDBY_SH="$INSTALL_DIR/standby.sh"
SERVICE_PATH="/etc/systemd/system/standby.service"

# Framebuffer: 800x480 BGRA
W=800
H=480
BPP=4
FRAME=$((W*H*BPP))   # 1536000

FPS=10
US_PER_FRAME=$((1000000 / FPS))

# Logging
RLOG="/tmp/autorun.log"

# single instance
LOCKDIR="/tmp/autorun.install.lock"
mkdir "$LOCKDIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

log(){ echo "$(date '+%H:%M:%S') $*" | tee -a "$RLOG" >&2; }

# ===================== helpers =====================
mount_usb() {
  [ -d "$USB_MNT" ] || mkdir -p "$USB_MNT" 2>/dev/null || true
  mount | grep -q "on $USB_MNT " && return 0

  for dev in /dev/sdc1 /dev/sdb1 /dev/sdd1 /dev/sda1; do
    [ -b "$dev" ] || continue
    mount "$dev" "$USB_MNT" 2>/dev/null && return 0
    mount -t vfat "$dev" "$USB_MNT" 2>/dev/null && return 0
    mount -t ext4 "$dev" "$USB_MNT" 2>/dev/null && return 0
  done
  return 1
}

remount_rw() {
  if mount -o remount,rw / 2>/dev/null; then
    log "Remounted / rw"
    return 0
  fi
  log "WARN: failed to remount / rw (may already be rw, or truly ro)"
  return 1
}

check_bgra() {
  # $1 = path
  p="$1"
  [ -f "$p" ] || { log "Missing $p"; exit 1; }
  SIZE=$(wc -c < "$p")
  FRAMES=$((SIZE / FRAME))
  REM=$((SIZE % FRAME))
  [ "$REM" -eq 0 ] || { log "$(basename "$p") invalid size=$SIZE rem=$REM"; exit 1; }
  [ "$FRAMES" -gt 0 ] || { log "$(basename "$p") has 0 frames"; exit 1; }
  echo "$FRAMES"
}

write_file() {
  tmp="$1.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$1"
}

# ===================== standby runtime script =====================
write_standby_runtime() {
  mkdir -p "$INSTALL_DIR"

  # Copy assets into persistent storage
  cp -f "$ANIM_USB" "$INSTALL_DIR/anim.bgra"
  cp -f "$START_USB" "$INSTALL_DIR/starting.bgra"
  [ -f "$HIT_USB" ] && cp -f "$HIT_USB" "$INSTALL_DIR/hit.bgra" || true
  [ -f "$BEEP_USB" ] && cp -f "$BEEP_USB" "$INSTALL_DIR/beep.u8.pcm" || true

  chmod 0644 "$INSTALL_DIR/anim.bgra" "$INSTALL_DIR/starting.bgra" 2>/dev/null || true
  chmod 0644 "$INSTALL_DIR/hit.bgra" 2>/dev/null || true
  chmod 0644 "$INSTALL_DIR/beep.u8.pcm" 2>/dev/null || true

  write_file "$STANDBY_SH" <<'EOF'
#!/bin/sh
set -eu

INSTALL_DIR="/init/efad/mp_sd/standby"
ANIM="$INSTALL_DIR/anim.bgra"
STARTING="$INSTALL_DIR/starting.bgra"
HIT="$INSTALL_DIR/hit.bgra"
BEEP="$INSTALL_DIR/beep.u8.pcm"

# Disable framebuffer blanking
if [ -w /sys/class/graphics/fb0/blank ]; then
  echo 0 > /sys/class/graphics/fb0/blank
fi

W=800; H=480; BPP=4
FRAME=$((W*H*BPP))
FPS=10
US_PER_FRAME=$((1000000 / FPS))

BC_USB="/dev/ttyUSB0"
BC_DEV="/dev/ttyS5"
BC_BAUD="115200"

NFC_DEV="/dev/ttymxc3"
NFC_BAUD="115200"

HIT_SECONDS=2
LOCK="/tmp/hit_lock"

WARMUP_SECONDS=10
PRIME_WAIT_SECONDS=10
NX_RUN_SECONDS=20

RLOG="/tmp/standby.log"
: > "$RLOG"
log(){ echo "$(date '+%H:%M:%S') $*" | tee -a "$RLOG" >&2; }

check_bgra() {
  p="$1"
  [ -f "$p" ] || { log "Missing $p"; exit 1; }
  SIZE=$(wc -c < "$p")
  FRAMES=$((SIZE / FRAME))
  REM=$((SIZE % FRAME))
  [ "$REM" -eq 0 ] || { log "$(basename "$p") invalid size=$SIZE rem=$REM"; exit 1; }
  [ "$FRAMES" -gt 0 ] || { log "$(basename "$p") has 0 frames"; exit 1; }
  echo "$FRAMES"
}

play_beep() {
  [ -f "$BEEP" ] || return 0
  command -v aplay >/dev/null 2>&1 || return 0
  aplay -q -D default -f U8 -r 8000 -c 1 "$BEEP" 2>/dev/null \
    || aplay -q -f U8 -r 8000 -c 1 "$BEEP" 2>/dev/null \
    || true
}

show_hit() {
  [ -f "$HIT" ] || return 0
  : > "$LOCK"
  log "HIT: show + beep"
  dd if="$HIT" of=/dev/fb0 bs=$FRAME count=1 2>/dev/null || true
  play_beep
  sleep "$HIT_SECONDS"
  rm -f "$LOCK"
}

play_anim_for_seconds() {
  FILE="$1"
  FRAMES="$2"
  SECS="$3"
  i=0
  end=$(( $(date +%s) + SECS ))
  while [ "$(date +%s)" -lt "$end" ]; do
    dd if="$FILE" of=/dev/fb0 bs=$FRAME count=1 skip=$i iflag=fullblock 2>/dev/null || true
    i=$((i+1)); [ "$i" -ge "$FRAMES" ] && i=0
    usleep "$US_PER_FRAME" 2>/dev/null || sleep 0.1
  done
}

prime_nx() {
  log "Prime: waiting ${PRIME_WAIT_SECONDS}s before starting NX"
  sleep "$PRIME_WAIT_SECONDS"

  log "Prime: starting NX (no-block)"
  systemctl start --no-block nx 2>/dev/null || true

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if pidof NxProx >/dev/null 2>&1; then
      log "NxProx started (pid=$(pidof NxProx))"
      break
    fi
    sleep 1
  done

  log "Letting NX run ${NX_RUN_SECONDS}s to init devices (create ttyS5 link, etc)"
  sleep "$NX_RUN_SECONDS"

  log "Prime: stopping NX + disabling PIC32 watchdog"
  systemctl stop nx 2>/dev/null || true
  NxExe watchdog 0 2>/dev/null || true

  log "Barcode dev link:"
  ls -l "$BC_DEV" >>"$RLOG" 2>&1 || true
}

barcode_watch() {
  [ -e "$BC_DEV" ] || { [ -e "$BC_USB" ] && ln -sf "$BC_USB" "$BC_DEV" 2>/dev/null || true; }
  [ -e "$BC_DEV" ] || { log "barcode_watch: missing $BC_DEV"; return 0; }

  stty -F "$BC_DEV" "$BC_BAUD" cs8 -cstopb -parenb -crtscts -ixon -ixoff raw -echo 2>/dev/null || true
  log "barcode_watch: watching $BC_DEV @ $BC_BAUD"

  while :; do
    : > /tmp/barcode.buf
    dd if="$BC_DEV" bs=1 count=512 2>/dev/null > /tmp/barcode.buf &
    ddpid=$!
    sleep 0.2
    kill "$ddpid" 2>/dev/null || true
    wait "$ddpid" 2>/dev/null || true

    n=$(wc -c < /tmp/barcode.buf | tr -d ' ')
    if [ "${n:-0}" -gt 0 ]; then
      data=$(tr -cd '[:print:]' < /tmp/barcode.buf 2>/dev/null | head -c 200 || true)
      log "BARCODE: $n bytes: $data"
      [ -f "$LOCK" ] || show_hit &
      usleep 250000 2>/dev/null || sleep 0.25
    fi
  done
}

nfc_watch() {
  [ -c "$NFC_DEV" ] || { log "nfc_watch: missing $NFC_DEV"; return 0; }

  stty -F "$NFC_DEV" "$NFC_BAUD" cs8 -cstopb -parenb -crtscts -ixon -ixoff raw -echo min 0 time 1 2>/dev/null || true
  log "nfc_watch: watching $NFC_DEV (tap = contains 00d1 record)"

  last_hit=0

  while :; do
    dd if="$NFC_DEV" bs=1 count=256 2>/dev/null > /tmp/nfc.buf || true
    [ -s /tmp/nfc.buf ] || continue

    hex=$(hexdump -v -e '1/1 "%02x"' /tmp/nfc.buf 2>/dev/null || true)
    echo "$hex" | grep -q "00d1" || continue

    now=$(date +%s)
    if [ $((now - last_hit)) -ge 1 ]; then
      last_hit="$now"
      log "NFC TAP (saw 00d1 frame)"
      [ -f "$LOCK" ] || show_hit &
    fi
  done
}

play_anim_loop() {
  FILE="$1"
  FRAMES="$2"
  log "Starting main animation loop (with watchers)"
  i=0
  while :; do
    if [ -f "$LOCK" ]; then
      usleep 50000 2>/dev/null || sleep 0.05
      continue
    fi
    dd if="$FILE" of=/dev/fb0 bs=$FRAME count=1 skip=$i iflag=fullblock 2>/dev/null || true
    i=$((i+1)); [ "$i" -ge "$FRAMES" ] && i=0
    usleep "$US_PER_FRAME" 2>/dev/null || sleep 0.1
  done
}

log "---- standby start ----"

START_FRAMES=$(check_bgra "$STARTING")
ANIM_FRAMES=$(check_bgra "$ANIM")

log "Warmup animation (starting.bgra) for ${WARMUP_SECONDS}s (no barcode/NFC watchers yet)"
play_anim_for_seconds "$STARTING" "$START_FRAMES" "$WARMUP_SECONDS"
log "Warmup animation stopped"

prime_nx || true

barcode_watch &
nfc_watch &

play_anim_loop "$ANIM" "$ANIM_FRAMES"
EOF

  chmod +x "$STANDBY_SH"
  log "Wrote $STANDBY_SH and copied assets into $INSTALL_DIR"
}

write_service() {
  # DEADLOCK FIX:
  # - DO NOT Requires=init-rc.service (init-rc often calls systemctl and would deadlock)
  # - Keep After=init-rc.service so we still start after boot scripts
  write_file "$SERVICE_PATH" <<EOF
[Unit]
Description=Standby Animation + Barcode/NFC triggers
After=init-rc.service

[Service]
Type=simple
ExecStart=$STANDBY_SH
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "$SERVICE_PATH" 2>/dev/null || true
  log "Wrote $SERVICE_PATH"
}

# ===================== main installer flow =====================
: > "$RLOG"
log "---- autorun install start ----"

mount_usb || { log "ERROR: could not mount USB"; exit 1; }

START_FRAMES=$(check_bgra "$START_USB")
ANIM_FRAMES=$(check_bgra "$ANIM_USB")
log "Starting frames: $START_FRAMES"
log "Animation frames: $ANIM_FRAMES"

# Make FS writable for service install (ok if it fails, but usually needed)
remount_rw || true

write_standby_runtime
write_service

# Enable + start (never block init scripts)
systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed standby.service init-rc.service 2>/dev/null || true
systemctl enable standby.service 2>/dev/null || true
systemctl start --no-block standby.service 2>/dev/null || true

log "Install done. Standby service should now be running."
log "Logs: /tmp/standby.log"
