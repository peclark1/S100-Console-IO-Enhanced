V29.11 SOURCE-GUIDED FONT UPDATE
=================================

The selectable font set is now:
  Default -> DEC VT220 -> IBM PC VGA -> Default

Default is the original Console I/O 8x12 font and is unchanged.
DEC VT220 is adapted to 8x12 from htayj/DEC-Fonts VT220 bitmap/BDF data.
IBM PC VGA is adapted to 8x12 from susam/pcface oldschool-vga-8x16.
All modes retain fixed 8x12 cells and native geometries 80x40 / 100x50 / 128x64.
Characters $00-$1F remain the Default font in every selection so DEC Special
Graphics is unchanged. See FONT-NOTICES.txt for source/provenance details.

V29.9b SELECTABLE FONT UPDATE
============================
Ctrl+Alt+F8 opens setup.  Press T to cycle:
  Default -> VT100-style -> IBM PC-style -> Default

All fonts use the same 8x12 cell, so screen geometry stays:
  640x480   = 80x40
  800x600   = 100x50
  1024x768  = 128x64

The selected font is persisted in EEPROM with resolution and colors.
Old V29.8 EEPROM settings remain compatible and load as Default font.
DEC Special Graphics glyphs are preserved identically in all fonts.

S-100 Console I/O Propeller firmware - switchable VGA + persistent settings
Version 29.6 full-screen + DEC graphics build, 2026-08-14

TOP OBJECT
----------
Open and compile:
    ConsoleIO-Switchable.spin

Display hotkeys
---------------
Ctrl+Alt+F1   640x480   / 80x40 characters
Ctrl+Alt+F2   800x600   / 100x50 characters
Ctrl+Alt+F3   1024x768  / 128x64 characters
Ctrl+Alt+F4   Cycle foreground color
Ctrl+Alt+F5   Cycle background color
Ctrl+Alt+F6   Swap foreground/background
Ctrl+Alt+F7   Reset colors to white on black

Keyboard scan-code display
--------------------------
The two on-board HEX display pairs now show both levels of keyboard decoding:

    Left pair   raw PS/2 Scan Code Set 2 make-code byte
    Right pair  translated character/code delivered to the S-100 host

Examples:
    A key       1C / 61     (lowercase a)
    Shift+A     1C / 41     (uppercase A)
    B key       32 / 62
    C key       21 / 63
    Enter       5A / 0D

Keyboard.spin keeps a 16-entry raw scan-code byte buffer in parallel with
its existing 16-entry translated-key buffer. This keeps each raw scan code
paired with the exact queued key returned by kb.key.

For E0-prefixed extended keys, the left display shows the byte following
E0 because the board provides only two HEX digits for the scan code.

Persistent settings
-------------------
The last selected resolution, foreground color, and background color are
saved automatically to the Propeller boot EEPROM and restored at startup.
No extra save keystroke is required.

The settings record is 8 bytes at EEPROM address $7FF0.  It contains a
signature, format version, mode, foreground/background colors, a trailer,
and a checksum.  Invalid/uninitialized records fall back safely to:

    1024x768 / 128x64
    white on black

The EEPROM interface uses the standard Propeller P1 boot-EEPROM pins:
    P28 = SCL
    P29 = SDA

Memory/design notes
-------------------
* One shared 8192-byte screen buffer supports all three resolutions.
* Three low-level VGA timing objects are compiled in; only one is running.
* Resolution changes stop/restart the VGA COGs and clear the terminal.
* Color changes are immediate and do not restart VGA.
* EEPROM writes occur only when the selected display settings actually change.
* The 8-byte record is written as a single small EEPROM page write.

Files
-----
ConsoleIO-Switchable.spin
VT100_Emulator-Switchable.spin
VGA_Switchable.spin
VGA_HiRes_Text_640.spin
VGA_HiRes_Text_800.spin
VGA_HiRes_Text_1024.spin
EEPROM_Settings.spin
Keyboard.spin
FullDuplexSerial.spin

V29.3 NOTE
---------
EEPROM I2C timing was corrected for Spin WAITCNT semantics.  The former
5 us delay used CNT first and could miss the target, effectively stalling
startup until the 32-bit system counter wrapped.  The EEPROM bit-bang delay
is now a conservative 100 us with CNT evaluated last.

V29.4 NOTE
---------
Added the raw PS/2 Scan Code Set 2 display feature requested in the original
Console I/O board notes. Keyboard.spin saves the raw make-code byte before
translation and places it in a parallel 16-entry buffer. The left HEX pair
now displays that raw scan code, while the right pair continues to display
the translated character/code sent to the S-100 host.

This is the same buffered scan-code method that was successfully tested on
the physical Console I/O V2 board before being merged into the V29.3
switchable-resolution/color/persistent-settings firmware.


VT100 DEC Special Graphics
--------------------------
V29.5 implements the G0 character-set designation used by VT100 terminals:

    ESC ( 0     Select DEC Special Graphics in G0
    ESC ( B     Return G0 to United States ASCII

The emulator now translates the standard DEC line-drawing characters onto
line-graphics glyphs which were already present in the original Parallax
8x12 VGA font. No changes to the 640x480, 800x600, or 1024x768 VGA font
objects are required.

Implemented line graphics:
    j  lower-right corner
    k  upper-right corner
    l  upper-left corner
    m  lower-left corner
    n  crossing
    q  horizontal line
    t  left tee
    u  right tee
    v  bottom tee
    w  top tee
    x  vertical line

VT100 alternate scan-line characters o, p, r, and s are accepted and mapped
to the available horizontal-line glyph. Other DEC Special Graphics symbols
are currently passed through unchanged.

A CP/M hardware test is included in the VTGRAPH_TEST folder. VTGRAPH.COM
selects DEC Special Graphics, draws boxes/tees/crossings, returns to ASCII,
and prints a completion message. It can be run directly under CP/M.


V29.5 NOTE
---------
Implemented the ESC-( G0 character-set state that the previous emulator
parsed but ignored. ESC ( 0 now enables DEC Special Graphics and ESC ( B
returns to normal ASCII. The mapping uses existing VGA control-code glyphs,
so the feature works identically in all three switchable resolutions and
preserves V29.4 raw keyboard scan-code display behavior.

V29.6 NOTE
---------
The V29.5 WarGames/DEC-graphics baseline already contained the native full-screen
geometry work: 80x40 at 640x480, 100x50 at 800x600, and 128x64 at 1024x768.
V29.6 preserves that known-good code and fixes one runtime-geometry correctness
issue in the VT100 DECSTBM (ESC [ top ; bottom r) scroll-region handler: top
and bottom are row numbers, so they are now bounded against termRows rather than
termCols. This matters most in the 100x50 and 128x64 modes.

Recommended hardware test:
  1. Compile ConsoleIO-Switchable.spin and load to RAM first.
  2. Ctrl+Alt+F1: verify 80 columns x 40 rows fill 640x480.
  3. Ctrl+Alt+F2: verify 100 columns x 50 rows fill 800x600.
  4. Ctrl+Alt+F3: verify 128 columns x 64 rows fill 1024x768.
  5. Run VTGRAPH.COM to confirm DEC Special Graphics still works.
  6. Power-cycle after selecting a mode/color to confirm EEPROM persistence.


V29.8 LOCAL SETUP UI
--------------------
Press Ctrl+Alt+F8 to open the local Console I/O setup/status screen.
It displays the active resolution/native geometry and foreground/background
colors. Changes can be previewed and either saved to EEPROM or cancelled.
See CHANGES-v29.8.txt for controls.
