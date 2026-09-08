# Interaction tests (QEMU monitor-driven)

Scripted end-to-end tests that drive headless QEMU through its monitor —
`sendkey` / `mouse_move` / `mouse_button` / `screendump` — plus AC'97 WAV
capture and `filter-dump` packet captures, so GUI, audio, and network
behavior get *evidence*, not just boot markers. Born in the 2026-08-25/26
desktop/audio/network session, where this harness caught bugs the serial
boot test and VirtualBox both hid (8042 aux-IRQ config, edge-trigger IRQ
starvation, an unstable spring integrator, missing PCI bus mastering).

Run under WSL Arch (qemu, ffmpeg, python3) after building `dist/`:

| script | proves |
|---|---|
| `shot-settings.sh` | dock click opens Settings; Right-arrow live-switches the UI theme |
| `shot-drag.sh` | titlebar grab/drag/release lands a window exactly at the drop point |
| `shot-files.sh` | Files window lists real lingfs, descends into `dev/` |
| `shot-wall-tray.sh` | ROYGBIV wallpaper switch; tray volume popover adjusts a per-app stream |
| `shot-audio.sh` | boot jingle's pentatonic notes present in the recorded WAV (Goertzel) |
| `shot-installed-boot.sh` | raw-disk boot -> VBE mode -> greeter -> real login -> desktop |
| `shot-lingfu.sh` | catalog sync + package download/install over real TCP/HTTP (`repo/` served by python) |
| `shot-horizon.sh` | horizon DOM/CSS/canvas layout; `fetch_raw` follows a 302 for the page *and* its `<img>`, PNG decodes and blits |

Conventions and gotchas (learned the hard way):
- HMP `mouse_move` uses screen convention (positive dy = down).
- QEMU's wav audiodev defaults to 44.1 kHz (pass `out.frequency=48000`)
  and leaves RIFF sizes zero unless closed cleanly — patch before parsing.
- TSC calibration under TCG runs tens of times fast: kernel-time timeouts
  and uptime displays are not wall time in these runs.
- A disk that has been installed to boots before the CD: pass `-boot d`
  when the CD is the intended boot device.
- Outputs land in `out/` beside the scripts.
