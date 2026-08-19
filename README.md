# S100 Console I/O Enhanced

Enhanced Propeller P1 firmware for John Monahan's S-100 Console I/O board.

This repository preserves the original Console I/O firmware lineage while adding the display, keyboard, terminal-emulation, and configuration enhancements developed and hardware-tested on a physical S-100 Console I/O V2 board.

<img width="2022" height="1554" alt="image" src="https://github.com/user-attachments/assets/a58e8008-2884-4060-a0e7-334215be3fee" />

## Current hardware-tested version

**V29.14** — 2026-08-14

The top-level object to open and compile is:

`ConsoleIO-Switchable.spin`

## Highlights

- Three full-screen VGA modes using a fixed 8x12 character cell:
  - **640x480 = 80x40**
  - **800x600 = 100x50**
  - **1024x768 = 128x64**
- Persistent resolution, foreground/background color, and font selection in the Propeller boot EEPROM.
- Ctrl+Alt+F8 local setup/status UI with live preview and explicit Save/Cancel behavior.
- Three selectable 8x12 fonts:
  - **Default** — original Console I/O / Parallax-derived font
  - **DEC VT220** — adapted from `htayj/DEC-Fonts`
  - **IBM PC VGA** — adapted from `susam/pcface` Oldschool PC VGA material
- Display/geometry calibration screen with exact-edge border, horizontal and vertical rulers, center crosshair, font samples, inverse-video sample, and color bars.
- Raw PS/2 Scan Code Set 2 make-code on the left HEX-display pair while the translated character/code remains on the right pair.
- VT100 `ESC ( 0` DEC Special Graphics line-drawing support, used by the CP/M WarGames display project.
- Runtime geometry-aware VT100 behavior across all three display sizes.

## Setup keys

Display hotkeys are local to the Console I/O firmware:

| Key | Function |
| --- | --- |
| Ctrl+Alt+F1 | 640x480 / 80x40 |
| Ctrl+Alt+F2 | 800x600 / 100x50 |
| Ctrl+Alt+F3 | 1024x768 / 128x64 |
| Ctrl+Alt+F4 | Cycle foreground color |
| Ctrl+Alt+F5 | Cycle background color |
| Ctrl+Alt+F6 | Swap foreground/background |
| Ctrl+Alt+F7 | Reset colors to white on black |
| Ctrl+Alt+F8 | Open local setup/status UI |

Inside the F8 setup screen, `T` cycles the fonts and `D` opens the display/geometry test. The setup screen provides the complete key legend, including Save and Cancel.

## Display geometry

All three modes use the same **8 x 12 pixel character cell**, so the native terminal geometry exactly fills the raster:

- 640 / 8 = 80 columns; 480 / 12 = 40 rows
- 800 / 8 = 100 columns; 600 / 12 = 50 rows
- 1024 / 8 = 128 columns; 768 / 12 = 64 rows

The VGA subsystem uses one shared maximum-size 8192-byte screen buffer and a runtime-configured renderer.

## Keyboard HEX display

The two on-board HEX-display pairs expose both levels of keyboard decoding:

- **Left pair:** raw PS/2 Scan Code Set 2 make-code byte
- **Right pair:** translated character/code delivered to the S-100 host

For example, lowercase `a` displays `1C / 61`.

## Persistent settings

Display settings are stored in a versioned record near the end of the Propeller P1 boot EEPROM. V29.14 stores video mode, foreground color, background color, and font. Older settings records remain backward compatible.

Reprogramming the Propeller EEPROM writes the boot image again, so saved display settings may need to be re-saved after reflashing firmware.

## Source layout

- `ConsoleIO-Switchable.spin` — top-level Console I/O firmware
- `VT100_Emulator-Switchable.spin` — terminal emulation and setup/test UI
- `VGA_Switchable.spin` — screen buffer, colors, mode/font selection
- `VGA_HiRes_Text_Runtime.spin` — runtime VGA PASM renderer and font data
- `Keyboard.spin` — PS/2 keyboard driver with parallel raw scan-code queue
- `EEPROM_Settings.spin` — persistent settings record
- `FullDuplexSerial.spin` — Parallax serial object used by the firmware
- `GEOMTEST.ASM` / `GEOMTEST.COM` — CP/M geometry diagnostic
- `CHANGES-v*.txt` — development notes for milestone builds
- `FONT-NOTICES.txt` — alternate-font provenance and licensing notes

## History and attribution

The original top-level Console I/O driver identifies **John Monahan** as its author (2011). The VGA and keyboard objects retain their original Parallax/Propeller authorship and license notices in the source. The VT100 emulator source also retains its upstream attribution.

The 2026 enhancement work is documented in the source revision history and `CHANGES-v*.txt` files.

## Font provenance / licensing

This repository contains material with **different upstream license/provenance histories**. In particular, the IBM PC VGA adaptation is derived from PC Face / Oldschool PC material documented as CC BY-SA 4.0, while DEC-Fonts has its own MIT-licensed contributions plus separately documented historical VT220 glyph provenance. See `FONT-NOTICES.txt` and the individual source headers for details.

Because the inherited firmware also contains older third-party code, this repository does **not** declare a new blanket license over all files. Preserve the existing notices and attribution when redistributing.

## Status

V29.14 has been compiled with Spin Tools IDE 0.57.2 and tested on the physical Console I/O board in all three VGA modes, including selectable fonts, persistent settings, DEC graphics, and the display/geometry test.
