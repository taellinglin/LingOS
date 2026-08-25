# Bare-Metal HDMI Audio on the Raspberry Pi 5 (BCM2712) — Research Report

*Researched 2026-08-25 for LingOS. No source code was modified; this document is the only deliverable.*

**TL;DR verdict:** Feasible, and much less blind than feared. Two independent open-source
bare-metal implementations of Pi 5 HDMI audio already exist and work on real hardware:
Circle's `CHDMISoundBaseDevice` (C++, since Circle Step 49) and Choominator's `rpi-hdmi`
(Rust, ~300 lines of core driver). The entire HDMI-audio path is on the BCM2712 die —
the RP1 southbridge is not involved at all. The firmware brings up HDMI video; a
bare-metal kernel only has to program the MAI FIFO, the audio clock divider (MAI_SMP),
N/CTS clock regeneration, the audio infoframe, and (optionally) a DMA40 channel.
There is no QEMU model for the Pi 5 (and QEMU does not model the HDMI audio block on
Pi 3 either), so final verification requires real hardware — but a staged plan
(Pi 3 polling → Pi 3 DMA → Pi 5 port) keeps each blind step small.

---

## 1. How Linux drives Pi 5 HDMI audio

### 1.1 Driver and variants

Pi 5 HDMI audio is driven by the **same `vc4_hdmi` driver** as Pi 0–4, with new
BCM2712 variants. In `drivers/gpu/drm/vc4/vc4_hdmi.c` (raspberrypi/linux, branch
`rpi-6.12.y`):

- Compatibles `brcm,bcm2712-hdmi0` / `brcm,bcm2712-hdmi1` bind to
  `bcm2712_hdmi0_variant` / `bcm2712_hdmi1_variant` (lines ~3538–3599). These use
  `vc6_hdmi_hdmi0_fields` / `vc6_hdmi_hdmi1_fields` register tables, the
  `vc6_hdmi_phy_init`/`vc6_hdmi_phy_disable` PHY hooks, and — importantly for audio —
  **no `phy_rng_enable`/`phy_rng_disable` hooks** (on Pi ≤ 4 an audio "RNG" power-up in
  the PHY was required; on BCM2712 it is not).
- The driver distinguishes two BCM2712 generations: `VC4_GEN_6_C` (original C1
  stepping) and `VC4_GEN_6_D` (**"D-step" / D0**). The DT compatible does *not*
  distinguish them; the KMS driver upgrades `VC4_GEN_6_C → VC4_GEN_6_D` at bind time
  by reading the HVS `SCALER6_VERSION` register
  (`drivers/gpu/drm/vc4/vc4_hvs.c`, ~line 2087: `SCALER6_VERSION_D0`), per the comment
  in `vc4_drv.c` line ~498: *"NB GEN_6_C will be corrected on D0 hw to GEN_6_D via
  vc4_hvs_bind"*.
- The only **audio-relevant D-step difference in the register set** is the MAI
  threshold register layout: `drivers/gpu/drm/vc4/vc4_regs.h` defines
  `VC4_HD_MAI_THR_*` fields (6-bit, shifts 0/8/16/24) versus `VC6_D_HD_MAI_THR_*`
  (7-bit, shifts 0/7/15/23). `vc4_hdmi_audio_prepare()` switches on `vc4->gen`
  (`VC4_GEN_6_C` vs `VC4_GEN_6_D`) when writing `HDMI_MAI_THR`.
- A cautionary note: `vc4_hdmi.c` ~line 913 contains
  *"TODO: This should work on BCM2712, but doesn't for some reason and result in a
  system lockup"* (about clearing `VID_CTL_ENABLE` on disable). That is the video
  path, but it shows BCM2712 still has unexplained behaviors even for the vendor.

### 1.2 The MAI FIFO path

MAI ("Multi-channel Audio Interface") is a small FIFO in the HDMI **"HD" register
block**; audio playback is simply: DMA (or the CPU) writes 32-bit words into
`HDMI_MAI_DATA`, paced by a DREQ line whose thresholds are set in `HDMI_MAI_THR`.

The full programming sequence lives in `vc4_hdmi.c`:

- `vc4_hdmi_audio_startup()` (~line 1969): write `HDMI_MAI_CTL =
  RESET | FLUSH | DLATE | ERRORE | ERRORF`.
- `vc4_hdmi_audio_set_mai_clock()` (~line 1890): compute a rational N/M with
  `rational_best_approximation(audio_clock_rate, samplerate, …)` and write
  `HDMI_MAI_SMP` (N in bits 31:8, M−1 in bits 7:0). The MAI sample clock is derived
  from the **"audio" clock** by this divider.
- `vc4_hdmi_set_n_cts()` (~line 1919): audio clock regeneration.
  `N = 128 * samplerate / 1000`, `CTS = mode_pixel_clock_hz * N / (128 * samplerate)`;
  writes `HDMI_CRP_CFG = EXTERNAL_CTS_EN | N` and the same CTS into `HDMI_CTS_0` and
  `HDMI_CTS_1`.
- `vc4_hdmi_audio_prepare()` (~line 2105), in order:
  `HDMI_MAI_CTL = CHNUM(channels) | WHOLSMP | CHALIGN | ENABLE`;
  `HDMI_MAI_FMT` = sample-rate code (`sample_rate_to_mai_fmt()`, ~line 2066: 48000→9,
  i.e. code `SAMPLE_RATE_8000`+index) plus format code PCM=2 (or HBR for 8-channel
  pass-through); `HDMI_MAI_THR` (gen-dependent, values 0x10/0x10/0x1C/0x1C on VC6);
  `HDMI_MAI_CONFIG = BIT_REVERSE | FORMAT_REVERSE | channel_mask`;
  `HDMI_MAI_CHANNEL_MAP` (identity map); `HDMI_AUDIO_PACKET_CONFIG =
  ZERO_DATA_ON_SAMPLE_FLAT | ZERO_DATA_ON_INACTIVE_CHANNELS | B_FRAME_IDENTIFIER(8) |
  CEA_MASK(channel_mask)`; then N/CTS; then the **audio infoframe** via
  `drm_atomic_helper_connector_hdmi_update_audio_infoframe()` (written into the HDMI
  packet RAM).

### 1.3 Sample format: IEC958 subframes built in software

The CPU DAI advertises exactly one format:
`vc4_hdmi_audio_cpu_dai_drv` (~line 2242–2253):
`.formats = SNDRV_PCM_FMTBIT_IEC958_SUBFRAME_LE`. The words DMA'd into `MAI_DATA`
are **pre-formatted IEC60958 subframes** (preamble bits, 24-bit sample, channel
status, parity), not raw PCM; `MAI_CONFIG`'s `BIT_REVERSE|FORMAT_REVERSE` handle bit
ordering. (ALSA/alsa-lib does the framing in userspace on Linux; a bare-metal driver
must do it itself — see §4.)

### 1.4 DMA

`vc4_hdmi_audio_init()` (~line 2327) registers a dmaengine PCM whose slave address is
the **physical address of `MAI_DATA` inside the "hd" reg range**, bus width 4 bytes,
`maxburst 2`; the channel name is (confusingly) `"audio-rx"`
(`pcm_conf`, ~line 2257).

Device tree (`arch/arm64/boot/dts/broadcom/bcm2712-rpi.dtsi`, `rpi-6.12.y`,
lines 261–279):

```dts
&dma32 { /* The VPU firmware uses DMA channel 11 for VCHIQ */
        brcm,dma-channel-mask = <0x03f>; };
&dma40 { brcm,dma-channel-mask = <0x07c0>; };
&hdmi0 { dmas = <&dma40 (10|(1<<30)|(1<<24)|(10<<16)|(15<<20))>;
         dma-names = "audio-rx"; };
&hdmi1 { dmas = <&dma40 (17|(1<<30)|(1<<24)|(10<<16)|(15<<20))>; ... };
```

- The DMA controller is the on-SoC **"DMA40"** (`brcm,bcm2712-dma`,
  `bcm2712-ds.dtsi` line ~334: `reg = <0x10 0x00010600>`, i.e. ARM physical
  `0x10_0001_0600`, channels 6–11, GIC SPIs 86–91; channel 11 is reserved for the
  VPU firmware's VCHIQ). **This is not the RP1** — HDMI audio never touches the
  southbridge.
- Decoding the cell against `drivers/dma/bcm2835-dma.c`: low bits = **DREQ 10**
  (HDMI0 MAI) / **17** (HDMI1 MAI); `(10<<16)` = QOS, `(15<<20)|(1<<24)` = panic QOS
  (`BCM2711_DMA40_QOS/PANIC_QOS`, lines 249–250), `(1<<30)` = burst hint
  (`BCM2835_DMA_BURST`, line 188).
- **On the D0 stepping the DREQ numbers change**: the `bcm2712d0` overlay
  (`arch/arm/boot/dts/overlays/bcm2712d0-overlay.dts`, lines 56–66) rewrites hdmi0 to
  DREQ **12** and hdmi1 to DREQ **13**.

### 1.5 Clocking

`vc5_hdmi_init_resources()` (`vc4_hdmi.c` lines ~3162–3184) takes four named clocks;
`bcm2712-rpi-5-b.dts` (lines 275–284) wires them as:

| clock-name | source on Pi 5 | driver use |
|---|---|---|
| `"hdmi"` | `<&firmware_clocks 13>` = `RPI_FIRMWARE_M2MC_CLK_ID` (HSM) | state machine clock |
| `"bvb"`  | `<&firmware_clocks 14>` = `RPI_FIRMWARE_PIXEL_BVB_CLK_ID` | pixel BVB clock |
| `"audio"`| `<&dvp 0>` — the DVP clock block (`brcm,brcm2711-dvp` at bus `0x7c700000`, parent `clk_108MHz`; `bcm2712.dtsi` line ~326) | **input to MAI_SMP divider; 108 MHz** |
| `"cec"`  | fixed 27 MHz | CEC |

Firmware clock IDs from `include/soc/bcm2835/raspberrypi-firmware.h` (13 = M2MC,
14 = PIXEL_BVB) — i.e. the HSM and BVB clocks are **owned by the VideoCore firmware
and get/set via the mailbox**, which is convenient for bare metal. The audio clock is
a fixed 108 MHz gate (Circle simply hardcodes `108000000UL` for Pi 4/5).

### 1.6 Register addresses (BCM2712)

From `bcm2712.dtsi` (hdmi node, bus addresses; ARM physical = bus `0x7cxx_xxxx` →
`0x10_7Cxx_xxxx`) and `vc4_hdmi_regs.h` (`vc6_hdmi_hdmi0_fields`, lines 431–530;
`vc6_hdmi_hdmi1_fields`, lines 531+):

| block | HDMI0 bus addr | ARM physical | contents |
|---|---|---|---|
| "hdmi" core | `0x7c701400` | `0x10_7C70_1400` | `AUDIO_PACKET_CONFIG` +0xC0, `RAM_PACKET_CONFIG` +0xC4, `RAM_PACKET_STATUS` +0xCC, `CRP_CFG` +0xD0, `CTS_0/1` +0xD4/+0xD8, `MAI_CHANNEL_MAP` +0xA4, `MAI_CONFIG` +0xA8 |
| "packet" RAM | `0x7c703800` | `0x10_7C70_3800` | infoframe packet RAM (9 words per packet slot; audio = slot 4) |
| "hd" | `0x7c720000` | `0x10_7C72_0000` | **shared by both controllers.** HDMI0: `MAI_CTL` +0x10, `MAI_THR` +0x14, `MAI_FMT` +0x18, `MAI_DATA` +0x1C, `MAI_SMP` +0x20. HDMI1: same registers at +0x30…+0x40 |

HDMI1's core/packet blocks are at bus `0x7c706400` / `0x7c708800`.

---

## 2. What the VideoCore firmware does on Pi 5 — and the (non-)existence of an audio service

### 2.1 Firmware architecture on Pi 5

There is **no `start.elf`/`start4.elf` on the Pi 5**; the bootloader and VPU firmware
live in the on-board EEPROM (`raspberrypi/rpi-eeprom`, `firmware-2712`; RISC OS Open
firmware notes: "There is no start.elf on Raspberry Pi 5 — just a flash-based
bootloader"). The firmware still runs on the VPU after OS handoff and still services
the **mailbox property interface**: board revision, clock get/set, and framebuffer
allocation all demonstrably work bare-metal on Pi 5 (Circle's `CMachineInfo`/
`CBcmFrameBuffer` use them; `rpi-hdmi` allocates its framebuffer with tags
`0x40001`/`0x40005`).

### 2.2 What firmware initializes for HDMI

When an HDMI display is connected, the firmware brings up the **entire video side**:
PHY/PLL, video timings at the EDID-preferred mode, the display pipeline for the
firmware framebuffer, and the RAM-packet (infoframe) engine. Evidence:

- Circle's HDMI sound driver *requires* it: `lib/sound/hdmisoundbasedevice.cpp`
  `Start()` refuses to run unless `RAM_PACKET_CONFIG` already has its enable bit
  (bit 16) set — error text: *"Requires HDMI display with audio support"* — i.e. the
  firmware (not Circle) enabled packet transmission.
- `rpi-hdmi` (`src/hdmi.rs` line ~101) allocates a framebuffer via the mailbox, then
  literally spin-waits "for the video core to prepare the HDMI registers" before
  touching audio registers.
- Circle's Pi 5 documentation (circle-rpi.readthedocs.io, appendix "Raspberry Pi 5")
  notes limits: *"The firmware support for frame buffer device(s) is not as
  comfortable on the Raspberry Pi 5 as on earlier models"* — no HDMI configuration
  via `config.txt`, no runtime resolution change from the application, DSI displays
  don't work.

What the firmware does **not** do: anything audio. No audio infoframe, no MAI/N/CTS
programming — both bare-metal drivers program all of those from scratch and audio
starts working only then. *(Confidence: high, but inferred from driver behavior, not
from firmware source, which is closed.)*

### 2.3 No mailbox audio service — confirmed

The official mailbox property interface documentation
(github.com/raspberrypi/firmware/wiki/Mailbox-property-interface) contains **no
audio-related tags whatsoever** — categories are firmware/hardware/config/DMA-sharing/
power/clocks/voltage/memory/EDID/framebuffer only. Historically, firmware audio on
Pi ≤ 4 was offered via the **VCHIQ** "AUDS" service (Linux `bcm2835-audio` ALSA
driver, Circle's VCHIQ sound addon), *not* the mailbox. On Pi 5 even that is gone:
the Pi 5 device trees (`bcm2712-rpi.dtsi`, `bcm2712-rpi-5-b.dts`) contain **no
`bcm2835-audio` and no VCHIQ audio node** (the only VCHIQ trace is a comment that the
VPU reserves DMA channel 11). There is also no PWM/analog audio path on Pi 5 at all.
Conclusion: **on Pi 5 there is no firmware-assisted audio of any kind; register-level
MAI programming is the only route.**

---

## 3. State of the art in bare-metal / hobby-OS Pi 5 audio

### 3.1 Circle (rsta2/circle) — yes, it supports Pi 5 HDMI audio

- Circle 46.0 (2024-02-28) introduced Pi 5 support (USB, networking, etc.).
- **Step/Release 49 (2024-11-08)** added *"HDMI sound for the Raspberry Pi 5"* and
  support for the **BCM2712 D0 stepping** (requires copying `overlays/bcm2712d0.dtbo`
  to the SD card). (`CHANGELOG.md`.)
- Caveat: Release 50.0 (2025-08-15) fixed *"The HDMI sound support with the class
  `CHDMISoundBaseDevice` did not work since Step 49"* — so use ≥ 50.0 as reference.
- Implementation: `lib/sound/hdmisoundbasedevice.cpp` +
  `include/circle/sound/hdmisoundbasedevice.h`. Notable properties:
  - One driver for Pi 1–5 via a 3-way register-address macro table (Pi ≤ 3 / Pi 4 /
    Pi 5 columns) — the Pi 5 column matches the Linux `vc6` offsets exactly
    (`include/circle/bcm2835.h`: `ARM_IO_BASE = 0x107C000000`,
    `ARM_HDMI_BASE = +0x701400`, `ARM_RAM_BASE = +0x703800`,
    `ARM_HD_BASE = +0x720000`).
  - Two modes: **polling** (busy-wait on `MAI_CTL.FULL`, CPU writes `MAI_DATA`) and
    **DMA** (double-buffered cyclic DMA to `MAI_DATA`).
  - Audio clock hardcoded 108 MHz on Pi 4/5; pixel clock for CTS read via mailbox
    `Get Clock Rate (PIXEL_BVB)`.
  - Detects the SoC stepping at runtime by reading register **`0x1001504004`**
    (`include/circle/bcm2712.h` `ARM_SOC_STEPPING`; value `0x2712_0021` = C1,
    `0x2712_0030` = D0 — see Raspberry Pi forums post p2247856) and switches both the
    **DREQ (10 → 12)** and the **MAI_THR field layout**.
  - IEC958 subframes are built in software
    (`lib/sound/soundbasedevice.cpp::ConvertIEC958Sample`, ~line 669: 24-bit sample
    << 4, channel-status bit 30, parity bit 31, B-preamble marker).
  - **HDMI0 only** (the header notes HDMI1 unsupported on Pi 4; the Pi 5 DREQ enum
    likewise only carries HDMI0 values 10/12 — `include/circle/dmacommon.h`).

### 3.2 Choominator/rpi-hdmi — a minimal Rust proof, for exactly this use case

`github.com/Choominator/rpi-hdmi` (default branch `rpi5`, `rpi4` branch for Pi 4;
now archived/read-only, last push 2026-08) is *"a working implementation of a bare
metal HDMI audio driver for the stepping C1 Raspberry Pi 5"*, in **Rust**. It plays
two square-wave tones on a 1080p green screen. Design (from its README and
`src/hdmi.rs`):

- *"I'm relying on the firmware to do most of the heavy lifting by configuring the
  video part through the Mailbox interface, and then driving the audio part myself."*
- All knowledge reverse-engineered from raspberrypi/linux (`bcm2712.dtsi`,
  `vc4_regs.h`, `vc4_hdmi_regs.h`, `vc4_hdmi.c`, `drivers/video/hdmi.c`,
  `include/linux/hdmi.h`, `include/sound/asoundef.h`) — *"which is very poorly
  explained"*.
- Core driver ≈ 292 lines; sets `MAI_CTL` with **`PAREN` (bit 8, hardware parity)**
  so software doesn't need to compute IEC958 parity; writes the audio infoframe
  directly into packet-RAM slot 4 (stride 9 words) with the checksum computed by
  hardware over the register block; hardcodes `CRP_CFG = EXTERNAL_CTS_EN | 6144`,
  `CTS = 148500` for 1080p60 (valid only because it assumes the firmware picked
  148.5 MHz).
- DMA: drives **DMA40-style channel 0 at ARM `0x10_0001_0000`** with two chained
  control blocks looping forever, `TI = 0xF348 | (DREQ << 16)`, DREQ 10
  (`src/dma.rs`).
- Practical gotcha recorded in its README: older Pi 5 firmware loaded bare-metal
  kernels at `0x200000`; current firmware uses `0x80000` — update firmware if the
  binary panics.

### 3.3 The broader Pi 5 bare-metal picture

- The **RP1 southbridge** (GPIO/UART/SPI/I2C/USB/Ethernet/I2S behind 4 lanes of
  PCIe 2.0) is the thing that makes general Pi 5 bare metal hard — but **HDMI and its
  audio FIFO/DMA are on the BCM2712 side** and unaffected. For other peripherals,
  `pciex4_reset=0` in `config.txt` leaves the firmware-initialized RP1 accessible
  (BCM2712 window `0x1F_0000_0000` → RP1 `0x40000000`; Raspberry Pi forums t=368402);
  Circle's docs state RP1 peripherals are usable on entry to `main()`.
- **No public BCM2712 datasheet exists** (forums t=393519; the official
  `bcm2712.adoc` is a marketing-level overview). RP1 has a public draft peripherals
  PDF, but again, RP1 is irrelevant to HDMI audio. Everything register-level in this
  document ultimately comes from Broadcom-authored GPL driver code in
  raspberrypi/linux — which two independent bare-metal projects have validated on
  hardware.
- **QEMU:** the official machine list stops at `raspi4b`
  (qemu.org/docs/master/system/arm/raspi.html); there is no Pi 5 model. Note also
  that even `raspi3b` does **not** model the HDMI blocks — QEMU maps the Pi 3 "DBUS"
  region `0x900000` (which contains the HDMI core) as an `unimplemented-device` stub
  (`hw/arm/bcm2835_peripherals.c` line ~526, `include/hw/arm/raspi_platform.h`), and
  the HD block at `0x808000` is not mapped at all. So HDMI-audio code can *run*
  under QEMU without crashing (reads-as-zero), but can never be *verified* there —
  on any Pi model. *(The exact behavior of accesses to the unmapped HD block region
  is uncertain; treat QEMU as "smoke test only".)*
- No other open-source bare-metal BCM2712 HDMI audio implementations were found
  beyond Circle and rpi-hdmi (searched: GitHub, Raspberry Pi forums, osdev circles).

---

## 4. Minimal register-level bring-up sequence (firmware has video up)

Synthesized from `vc4_hdmi.c` (`vc4_hdmi_audio_startup/prepare`, `vc4_hdmi_set_n_cts`),
Circle `hdmisoundbasedevice.cpp` (`RunHDMI/Start/SetAudioInfoFrame`), and
`rpi-hdmi/src/hdmi.rs`. Addresses are ARM physical for **HDMI0 on Pi 5**; 2-channel
48 kHz PCM assumed.

0. **Preconditions.** Firmware booted with an HDMI display attached and video up.
   Sanity check: `RAM_PACKET_CONFIG` (`0x10_7C70_14C4`) bit 16 set (packet engine
   enabled ⇒ HDMI mode, not DVI). Detect stepping: read `0x10_0150_4004`; high half
   `0x2712`, low byte `0x21` = C1, `0x30` = D0.
1. **Reset MAI.** `MAI_CTL` (`0x10_7C72_0010`) = `RESET|FLUSH|DLATE|ERRORE|ERRORF`
   (bits 0,9,15,2,1).
2. **MAI sample clock.** `MAI_SMP` (`0x10_7C72_0020`) = `N<<8 | (M−1)` where
   `N/M ≈ 108 MHz / fs` (48 kHz → N=2250, M=1). (Linux uses
   `rational_best_approximation`; Circle ports the same routine.)
3. **MAI format.** `MAI_FMT` (`0x10_7C72_0018`) = rate-code<<8 | 2<<16 (PCM;
   48 kHz code = 9).
4. **FIFO thresholds.** `MAI_THR` (`0x10_7C72_0014`):
   C1: `0x10<<24 | 0x10<<16 | 0x1C<<8 | 0x1C`;
   D0: same values at shifts 23/15/7/0 (7-bit fields).
5. **MAI config.** `MAI_CONFIG` (`0x10_7C70_14A8`) =
   `BIT_REVERSE(26) | FORMAT_REVERSE(27) | channel_mask 0b11`.
6. **Channel map.** `MAI_CHANNEL_MAP` (`0x10_7C70_14A4`) = `0x10` (ch0→0, ch1→1).
7. **Audio packet config.** `AUDIO_PACKET_CONFIG` (`0x10_7C70_14C0`) =
   `ZERO_ON_FLAT(29) | ZERO_INACTIVE(24) | 0x8<<10 (B-frame id) | 0b11 (CEA mask)`.
8. **Clock regeneration.** `N = 128*fs/1000` (48 kHz → 6144);
   `CTS = pixel_clock_Hz * N / (128*fs)`. Write `CRP_CFG` (`0x10_7C70_14D0`) =
   `1<<24 (EXTERNAL_CTS_EN) | N`; `CTS_0/CTS_1` (`+0xD4/+0xD8`) = CTS.
   Get the pixel clock via mailbox `Get Clock Rate` of `PIXEL_BVB` (id 14), as Circle
   does — do **not** hardcode 148.5 MHz unless the mode is known.
9. **Audio InfoFrame.** Clear bit 4 (audio packet id) in `RAM_PACKET_CONFIG`, poll
   `RAM_PACKET_STATUS` (`+0xCC`) bit 4 clear; write the CEA audio infoframe into
   packet RAM slot 4 (`0x10_7C70_3800 + 4*9*4`): word0 = `0x0A0184`
   (type 0x84, version 1, length 10), word1 = channel-count/allocation (Circle uses
   `0x0170` incl. checksum; rpi-hdmi lets hardware checksum and encodes
   2ch/48 kHz/16-bit), zero the remaining 7 words; set bit 4 again and poll status
   set.
10. **Enable.** `MAI_CTL` = `CHNUM(2)<<4 | WHOLSMP(12) | CHALIGN(13) | ENABLE(3)`
    (+ optionally `PAREN(8)` for hardware parity).
11. **Feed the FIFO.** Either poll `MAI_CTL.FULL` (bit 11) and CPU-write
    `MAI_DATA` (`0x10_7C72_001C`), or set up a cyclic DMA40 transfer
    (controller at `0x10_0001_0xxx`, 32-bit writes, paced by
    **DREQ 10 (C1) / 12 (D0)**; HDMI1 would be 17/13 and MAI regs at HD +0x30…0x40).
12. **Word format.** Each 32-bit word is one IEC60958 subframe:
    bits 3:0 preamble (8 marks a B frame, i.e. block start, every 192 frames×2ch),
    bits 27:4 = 24-bit sample (16-bit audio shifted left), bit 30 = channel-status
    bit for this frame, bit 31 = parity (unless `PAREN`). Channel status must encode
    consumer/PCM/48 kHz/word length, per `include/sound/asoundef.h`.

**Documentation status:** none of this is publicly documented for BCM2712 by
Broadcom or Raspberry Pi. It is 100 % derived from the vendor-authored GPL Linux
driver (`vc4_hdmi.c` / `vc4_regs.h` / `vc4_hdmi_regs.h`) plus DT, and independently
validated on hardware by Circle and rpi-hdmi. The register *names/semantics* are
high-confidence; anything not exercised by those three codebases (HBR pass-through,
>2 channels on Pi 5, HDMI1 audio on Pi 5) should be treated as untested.

---

## 5. Feasibility verdict and staged plan

### Verdict

**Feasible — this is a "port a known-good sequence" problem, not a research problem.**
The existence of Circle ≥ 50.0 and rpi-hdmi means every register write needed on a
real Pi 5 (both steppings, in Circle's case) is already known and proven. The real
risks are (a) LingOS-side integration bugs that can't be observed in QEMU (DMA
address translation, cache maintenance on the DMA buffer, wrong stepping handling),
(b) environment variance (monitor EDID/mode changes the pixel clock and hence CTS;
some displays are picky about channel status/infoframes), and (c) firmware version
drift (load address `0x200000` → `0x80000` history; Circle requiring "the new DTB
files" for recent releases).

### What can be built blind vs. what needs hardware

- **Blind-buildable (host-testable):** IEC958 subframe encoder + channel-status
  block, N/CTS math, infoframe serialization + checksum, ring buffer/mixer. These are
  pure functions — unit-test them in the LingOS build on the host or under QEMU.
- **Blind-risky (needs a Pi 5 in the loop):** MAI register writes, DMA40 setup,
  stepping detection, timing of firmware HDMI readiness. Mitigation: the hardware
  itself gives feedback even without ears — read back `MAI_CTL` (FULL/EMPTY/error/
  starvation bits), `RAM_PACKET_STATUS`, DMA channel CS/error registers, and log via
  serial. Per the project's own lesson that framebuffer regressions are invisible to
  serial-only tests, define "success" registers-first: *FIFO drains + no ERRORF/E +
  packet-status bit set* before trusting a listening test.

### Staged plan

1. **Stage A — Pi 3, polling (smallest blind step).** LingOS already boots on real
   Pi 3. Implement the same sequence with Circle's Pi ≤ 3 column: HDMI core
   `0x3F90_2000`, HD `0x3F80_8000`, HSM/pixel clocks read from CPRMAN/PLLH
   (`GetHSMClockRate`/`GetPixelClockRate` in `hdmisoundbasedevice.cpp`), DREQ 17,
   and a PHY RNG power-up bit. No DMA: poll `MAI_CTL.FULL`, write `MAI_DATA`.
   QEMU `raspi3b` will at least execute this path (HDMI regs are stubs).
   Deliverable: audible tone on a real Pi 3 over HDMI.
2. **Stage B — Pi 3, DMA.** Add a bcm2835 DMA channel doing cyclic double-buffered
   writes to `MAI_DATA` with DREQ pacing + completion IRQ. This debugs the DMA/cache
   discipline on hardware LingOS already supports.
3. **Stage C — Pi 5 port.** Swap constants: bases `0x10_7C70_1400` /
   `0x10_7C70_3800` / `0x10_7C72_0000`; audio clock fixed 108 MHz; pixel clock via
   mailbox `PIXEL_BVB`; stepping register `0x10_0150_4004` choosing DREQ 10/12 and
   the MAI_THR layout; DMA40 controller at `0x10_0001_0xxx` with 40-bit control
   blocks (or start in polling mode first, which needs *no* DMA at all and is the
   fastest possible "first sound on Pi 5"). Keep `kernel_2712.img` naming and current
   firmware per Circle's boot notes.
4. **Stage D — hardening.** Multiple sample rates, HDMI1 (HD +0x30 regs,
   DREQ 17/13 — *untested anywhere*, expect surprises), 5.1/8-channel and HBR,
   hot-plug/mode-change handling (recompute CTS), and a register-readback self-test
   that runs on every boot.

Size estimate: Circle's entire multi-generation driver is 794 lines; a Pi 5-only
polling driver is realistically 150–300 lines of LingOS kernel code plus the IEC958
encoder.

---

## Sources

**Linux (raspberrypi/linux, branch `rpi-6.12.y`)**
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/gpu/drm/vc4/vc4_hdmi.c — audio startup/prepare/set_mai_clock/set_n_cts (~lines 1890–2225), audio_init/DMA (~2327–2460), BCM2712 variants (~3538–3599), BCM2712 lockup TODO (~913)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/gpu/drm/vc4/vc4_hdmi_regs.h — `vc6_hdmi_hdmi0_fields` (431–530), `vc6_hdmi_hdmi1_fields` (531+)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/gpu/drm/vc4/vc4_regs.h — `VC4_HD_MAI_CTL_*` (960–979), `VC4_HD_MAI_THR_*` vs `VC6_D_HD_MAI_THR_*` (981–997), `VC4_HD_MAI_SMP_*` (1002–1005), `VC4_HDMI_CRP_CFG_*` (803–809)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/gpu/drm/vc4/vc4_hvs.c — D0 detection via `SCALER6_VERSION` (~2087)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/gpu/drm/vc4/vc4_drv.c — `VC4_GEN_6_C` compatible + D0-correction comment (~498)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm64/boot/dts/broadcom/bcm2712.dtsi — hdmi0/hdmi1 reg maps, `dvp` clock node
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm64/boot/dts/broadcom/bcm2712-rpi.dtsi — hdmi dmas/DREQ, DMA channel masks, VCHIQ ch-11 comment (261–279)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm64/boot/dts/broadcom/bcm2712-rpi-5-b.dts — hdmi clocks (275–284)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm64/boot/dts/broadcom/bcm2712-ds.dtsi — `dma40: dma@10600`, `brcm,bcm2712-dma` (~334)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/arch/arm/boot/dts/overlays/bcm2712d0-overlay.dts — D0 DREQ 12/13 (56–66)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/drivers/dma/bcm2835-dma.c — DMA40 QOS/flag encoding (188, 249–255)
- https://github.com/raspberrypi/linux/blob/rpi-6.12.y/include/soc/bcm2835/raspberrypi-firmware.h — firmware clock IDs (166–182)
- https://github.com/raspberrypi/linux/issues/6656 — example of Pi 5 HDMI-audio regression reports against vc4_hdmi

**Firmware / mailbox**
- https://github.com/raspberrypi/firmware/wiki/Mailbox-property-interface — full tag list; no audio tags
- https://github.com/raspberrypi/rpi-eeprom — Pi 5 (`firmware-2712`) EEPROM bootloader
- https://www.riscosopen.org/wiki/documentation/show/Software%20information:%20Raspberry%20Pi:%20Firmware — "no start.elf on Raspberry Pi 5"

**Circle**
- https://github.com/rsta2/circle/blob/master/CHANGELOG.md — Pi 5 support (46.0), Pi 5 HDMI sound + D0 (Step 49, 2024-11-08), HDMI-sound fix (50.0, 2025-08-15)
- https://github.com/rsta2/circle/blob/master/lib/sound/hdmisoundbasedevice.cpp — the driver (register table 34–119, `Start` 189–295, `RunHDMI` 366–448, `SetAudioInfoFrame` ~533)
- https://github.com/rsta2/circle/blob/master/lib/sound/soundbasedevice.cpp — `ConvertIEC958Sample` (~669)
- https://github.com/rsta2/circle/blob/master/include/circle/bcm2835.h — Pi 5 `ARM_IO_BASE 0x107C000000`, HDMI bases (373–387)
- https://github.com/rsta2/circle/blob/master/include/circle/bcm2712.h — `ARM_SOC_STEPPING 0x1001504004`
- https://github.com/rsta2/circle/blob/master/include/circle/dmacommon.h — `DREQSourceHDMI 10` / `DREQSourceHDMI_D0 12`
- https://github.com/rsta2/circle/blob/master/lib/machineinfo.cpp — stepping read (~288–295)
- https://circle-rpi.readthedocs.io/en/latest/appendices/raspberry-pi-5.html — Pi 5 limitations, required boot files (`kernel_2712.img`, `bcm2712d0.dtbo`)
- https://forums.raspberrypi.com/viewtopic.php?p=2247906#p2247856 — stepping register discovery

**Bare-metal reference implementation**
- https://github.com/Choominator/rpi-hdmi — Rust bare-metal Pi 5 (C1) HDMI audio; `src/hdmi.rs`, `src/dma.rs`; `rpi4` branch for Pi 4; archived
- https://forums.raspberrypi.com/viewtopic.php?t=306441 — "bare metal hdmi audio" forum thread (Pi 4-era reverse engineering)

**Pi 5 platform / RP1 / steppings**
- https://forums.raspberrypi.com/viewtopic.php?t=368402 — RP1 access from BCM2712, `pciex4_reset=0`, `0x1F_0000_0000` window
- https://forums.raspberrypi.com/viewtopic.php?t=393519 — no public BCM2712 datasheet
- https://github.com/raspberrypi/documentation/blob/master/documentation/asciidoc/computers/processors/bcm2712.adoc — official BCM2712 overview
- https://picockpit.com/raspberry-pi/i-read-the-rp1-documentation-so-you-dont-have-to/ — RP1 peripherals summary
- https://www.raspberrypi.com/news/2gb-raspberry-pi-5-on-sale-now-at-50/ and https://hackaday.com/2024/08/19/cost-optimized-raspberry-pi-5-released-with-2-gb-ram-and-d0-stepping/ — D0 stepping introduction (2024-08)
- https://www.jeffgeerling.com/blog/2024/new-2gb-pi-5-has-33-smaller-die-30-idle-power-savings/ — D0 die changes

**QEMU**
- https://www.qemu.org/docs/master/system/arm/raspi.html — machine list ends at `raspi4b` (no Pi 5)
- https://github.com/qemu/qemu/blob/master/hw/arm/bcm2835_peripherals.c + https://github.com/qemu/qemu/blob/master/include/hw/arm/raspi_platform.h — Pi ≤ 3 HDMI region (`DBUS_OFFSET 0x900000`) is an unimplemented stub
