{{
 Switchable VGA terminal display object for the S-100 Console I/O board.
 Derived from VGA_1024.spin by Andy Valencia / Vince Briel / Jeff Ledger.
 Resolution switching additions prepared for the S-100 Console I/O board.

 Modes:
   0 = 640x480   / 80x40 characters
   1 = 800x600   / 100x50 characters
   2 = 1024x768  / 128x64 characters

 One maximum-size screen buffer is shared by all three modes.
 V29.7 uses a single runtime-patched VGA PASM/font object so video timing and
 character geometry are selected together. V29.11 uses Default, DEC VT220, and IBM PC VGA selectable 8x12 fonts.
}}

CON
    MODE_80x40   = 0
    MODE_100x50  = 1
    MODE_128x64  = 2

    FONT_DEFAULT  = 0
    FONT_VT100    = 1
    FONT_IBMPC    = 2

    MAX_COLS     = 128
    MAX_ROWS     = 64
    MAX_CHARS    = MAX_COLS * MAX_ROWS

    GOLDBLUE     = $08F0
    CYANBLUE     = $2804
    WHITEBLACK   = $00FF
    GREENBLACK   = $0020

OBJ
    vga : "VGA_HiRes_Text_Runtime"

VAR
    byte screen[MAX_CHARS]      ' One shared 8192-byte screen buffer
    word colors[MAX_ROWS]       ' One color word per possible row
    byte cursor[6]
    long sync
    byte inverse
    byte foregroundColor
    byte backgroundColor
    byte fgChoice
    byte bgChoice
    byte tmpl[MAX_COLS]         ' Temp buffer for insert-character operation

    long savedBasePin
    long currentMode
    long currentFont
    long screenCols
    long screenRows
    long screenChars
    long screenLastLine
    long screenLongCols
    long screenLongChars

PUB start(BasePin, InitialMode, InitialForeground, InitialBackground, InitialFont) : okay
    savedBasePin := BasePin

    ' Load the requested startup colors before starting the VGA COGs.
    ' The caller may supply saved EEPROM values or the normal defaults.
    setColors(InitialForeground, InitialBackground)

    if (InitialFont < FONT_DEFAULT) or (InitialFont > FONT_IBMPC)
        currentFont := FONT_DEFAULT
    else
        currentFont := InitialFont

    okay := setMode(InitialMode)

PUB setMode(NewMode) : okay
    if (NewMode < MODE_80x40) or (NewMode > MODE_128x64)
        return 0

    stop
    configure(NewMode)

    ' Prepare display memory before the new VGA COGs start reading it.
    bytefill(@screen, $20, MAX_CHARS)
    applyColors
    bytefill(@cursor, 0, 6)
    cursor[2] := %110                   ' underscore, slow blink
    inverse := 0
    sync := 0

    ' One VGA object owns the PASM/font image.  Its start() method patches both
    ' timing and native character geometry from currentMode before launching.
    okay := vga.start(savedBasePin, @screen, @colors, @cursor, @sync, currentMode, currentFont)

    if okay
        waitcnt(clkfreq * 1 + cnt)      ' preserve original VGA startup delay

PUB stop
    vga.stop

PUB getMode : value
    value := currentMode

PUB setFont(NewFont) : okay
    if (NewFont < FONT_DEFAULT) or (NewFont > FONT_IBMPC)
        return 0

    if NewFont == currentFont
        return 1

    ' Font selection does not change screen geometry or contents.  Restart the
    ' two VGA cogs with the new font pointer while preserving the screen buffer.
    vga.stop
    currentFont := NewFont
    sync := 0
    okay := vga.start(savedBasePin, @screen, @colors, @cursor, @sync, currentMode, currentFont)
    if okay
        waitcnt(clkfreq / 4 + cnt)

PUB cycleFont : value
    value := (currentFont + 1) // 3
    if setFont(value) == 0
        value := currentFont

PUB getFont : value
    value := currentFont

PUB getCols : value
    value := screenCols

PUB getRows : value
    value := screenRows

PUB getChars : value
    value := screenChars

PUB getLastLine : value
    value := screenLastLine

PRI configure(NewMode)
    currentMode := NewMode

    case currentMode
        MODE_80x40:
            screenCols := 80
            screenRows := 40
        MODE_100x50:
            screenCols := 100
            screenRows := 50
        MODE_128x64:
            screenCols := 128
            screenRows := 64

    screenChars := screenCols * screenRows
    screenLastLine := (screenRows - 1) * screenCols
    screenLongCols := screenCols / 4
    screenLongChars := screenChars / 4

PUB setColor(val)
    ' Keep compatibility with the original VGA_1024 interface.
    setColors(val & $FC, (val >> 8) & $FC)

PUB setRowColors(row, foreground, background)
    ' Test/calibration helper: set one displayed text row without changing
    ' the persistent/current global foreground/background selection.
    if (row => 0) and (row < MAX_ROWS)
        colors[row] := ((background & $FC) << 8) | (foreground & $FC)

PUB setColors(foreground, background)
    ' VGA hardware uses only bits 7..2 of each color byte (%RRGGBB00).
    foregroundColor := foreground & $FC
    backgroundColor := background & $FC
    fgChoice := foregroundIndex(foregroundColor)
    bgChoice := backgroundIndex(backgroundColor)
    applyColors

PUB cycleForeground
    fgChoice := (fgChoice + 1) // 10
    foregroundColor := foregroundPalette(fgChoice)
    if foregroundColor == backgroundColor
        fgChoice := (fgChoice + 1) // 10
        foregroundColor := foregroundPalette(fgChoice)
    applyColors

PUB cycleBackground
    bgChoice := (bgChoice + 1) // 9
    backgroundColor := backgroundPalette(bgChoice)
    if backgroundColor == foregroundColor
        bgChoice := (bgChoice + 1) // 9
        backgroundColor := backgroundPalette(bgChoice)
    applyColors

PUB swapColors | t
    t := foregroundColor
    foregroundColor := backgroundColor
    backgroundColor := t
    fgChoice := foregroundIndex(foregroundColor)
    bgChoice := backgroundIndex(backgroundColor)
    applyColors

PUB resetColors
    foregroundColor := $FC
    backgroundColor := $00
    fgChoice := 0
    bgChoice := 0
    applyColors

PUB getForeground : value
    value := foregroundColor

PUB getBackground : value
    value := backgroundColor

PRI applyColors | val
    val := (backgroundColor << 8) | foregroundColor
    ' Fill all 64 row entries so the selected colors survive a later switch
    ' to a mode with more rows.
    wordfill(@colors, val, MAX_ROWS)

PRI foregroundIndex(value) : result | i
    result := 0
    repeat i from 0 to 9
        if foregroundPalette(i) == value
            result := i
            return

PRI backgroundIndex(value) : result | i
    result := 0
    repeat i from 0 to 8
        if backgroundPalette(i) == value
            result := i
            return


PRI foregroundPalette(i) : value
    ' Bright/classic terminal foreground choices.  VGA byte format is
    ' %RRGGBB00, two bits (four levels) per component.
    case i
        0:
            value := $FC                 ' white
        1:
            value := $30                 ' green
        2:
            value := $E0                 ' amber
        3:
            value := $3C                 ' cyan
        4:
            value := $F0                 ' yellow
        5:
            value := $C0                 ' red
        6:
            value := $CC                 ' magenta
        7:
            value := $0C                 ' blue
        8:
            value := $A8                 ' gray
        9:
            value := $00                 ' black

PRI backgroundPalette(i) : value
    ' Mostly dark choices make useful terminal backgrounds; white is included
    ' so black-on-white is also available.
    case i
        0:
            value := $00                 ' black
        1:
            value := $04                 ' dark blue
        2:
            value := $08                 ' medium blue
        3:
            value := $10                 ' dark green
        4:
            value := $14                 ' dark cyan
        5:
            value := $40                 ' dark red
        6:
            value := $44                 ' dark magenta
        7:
            value := $54                 ' dark gray
        8:
            value := $FC                 ' white


PUB setInv(c)
    inverse := c

PUB setCursor(c) | i
    i := %000
    if c == 1
        i := %001
    elseif c == 2
        i := %010
    elseif c == 3
        i := %011
    elseif c == 4
        i := %101
    elseif c == 5
        i := %110
    elseif c == 6
        i := %111
    elseif c == 7
        i := %000
    cursor[2] := i

PUB cls
    ' Clear the full shared buffer so a later larger mode cannot reveal old text.
    bytefill(@screen, $20, MAX_CHARS)

PUB clEOL(pos) | count
    count := screenCols - (pos // screenCols)
    bytefill(@screen + pos, $20, count)

PUB clBOL(pos) | count
    count := pos // screenCols
    bytefill(@screen + pos - count, $20, count)

PUB delLine(pos) | src, count
    pos -= pos // screenCols
    src := pos + screenCols
    count := (screenChars - src) / 4
    if count > 0
        longmove(@screen + pos, @screen + src, count)
    longfill(@screen + screenLastLine, $20202020, screenLongCols)

PUB clEOS(pos)
    clEOL(pos)
    pos += screenCols - (pos // screenCols)
    repeat while pos < screenChars
        longfill(@screen + pos, $20202020, screenLongCols)
        pos += screenCols

PUB setCursorPos(pos)
    cursor[0] := pos // screenCols
    cursor[1] := pos / screenCols

PUB insLine(pos) | base, nxt
    base := pos - (pos // screenCols)
    pos := screenLastLine
    repeat while pos > base
        nxt := pos - screenCols
        longmove(@screen + pos, @screen + nxt, screenLongCols)
        pos := nxt
    clEOL(base)

PUB insChar(pos) | count
    count := (screenCols - (pos // screenCols)) - 1
    bytemove(@tmpl, @screen + pos, count)
    screen[pos] := " "
    bytemove(@screen + pos + 1, @tmpl, count)

PUB delChar(pos) | count
    count := (screenCols - (pos // screenCols)) - 1
    bytemove(@screen + pos, @screen + pos + 1, count)
    screen[pos + count] := " "

PUB putc(pos, c)
    if inverse
        c |= $80
    screen[pos] := c

PUB saveBox(dest, row, col, nrow, ncol) | x, ptr
    ptr := @screen + row * screenCols + col
    repeat x from 0 to nrow - 1
        bytemove(dest, ptr, ncol)
        dest += ncol
        ptr += screenCols

PUB restoreBox(src, row, col, nrow, ncol) | x, ptr
    ptr := @screen + row * screenCols + col
    repeat x from 0 to nrow - 1
        bytemove(ptr, src, ncol)
        src += ncol
        ptr += screenCols

PUB fillBox(row, col, nrow, ncol, val) | x, ptr
    ptr := @screen + row * screenCols + col
    repeat x from 0 to nrow - 1
        bytefill(ptr, val, ncol)
        ptr += screenCols
