{{
        Code from the ajv Terminal emulator
        Runtime geometry added for switchable 80x40 / 100x50 / 128x64 display modes.
        V29.6: ANSI scroll-region parameters are bounded by rows, not columns.
        V29.7: Geometry is derived directly from the selected VGA mode and kept
               in longs; ANSI CUP/HVP clamps row and column independently.
''
'' Based on code from Vince Briel and ajv

}}
OBJ
    text:       "VGA_Switchable"          ' Switchable VGA Terminal Driver

VAR
    'terminal emulation vars
    byte force7 '  force7 - Flag force to 7 bits
    byte autolf '  autolf - Generate LF after CR
    byte state  ' Main terminal emulation state
    long a0     '  Arg 0 to an escape sequence
    long a1     '   ...arg 1
    byte onlast ' Flag that we've just put a char on last column
    word pos    ' Current output/cursor position

    byte savemins ' # minutes until blank screen
    byte color  ' Text color (index)
    byte baud   ' Baud rate (index)
    byte cursor ' Cursor style
    long regTop, regBot ' Scroll region top/bottom
    long termCols, termRows, termChars, termLastLine ' Runtime display geometry
    byte lastc  ' Last displayed character
    byte g0graphics ' DEC Special Graphics selected in G0 by ESC ( 0

PUB start(video, mode, foreground, background, font)
    ' Start with settings supplied by ConsoleIO.  These may have come from
    ' the boot EEPROM, or may be the normal 128x64 white-on-black defaults.
    text.start(video, mode, foreground, background, font)
    syncGeometry

PUB setMode(mode) : okay
    okay := text.setMode(mode)
    if okay
        init

PUB getMode : mode
    mode := text.getMode

PUB setFont(font) : okay
    okay := text.setFont(font)

PUB cycleFont : font
    font := text.cycleFont

PUB getFont : font
    font := text.getFont

PUB cycleForeground
    text.cycleForeground

PUB cycleBackground
    text.cycleBackground

PUB swapColors
    text.swapColors

PUB resetColors
    text.resetColors

PUB setColors(foreground, background)
    text.setColors(foreground, background)

PUB setRowColors(row, foreground, background)
    text.setRowColors(row, foreground, background)

PUB getForeground : value
    value := text.getForeground

PUB getBackground : value
    value := text.getBackground

PRI syncGeometry | mode
    ' Derive the VT100 geometry from the same mode value that selected VGA.
    ' This deliberately avoids a chain of byte/word geometry getters.
    mode := text.getMode
    case mode
        0:
            termCols := 80
            termRows := 40
        1:
            termCols := 100
            termRows := 50
        OTHER:
            termCols := 128
            termRows := 64

    termChars := termCols * termRows
    termLastLine := (termRows - 1) * termCols

'' Initialize terminal emulator code
PUB init

    syncGeometry
    text.cls

    ' Init state vars
    state := 0
    g0graphics := 0
    onlast := 0
    pos := 0
    regTop := 0
    regBot := termChars

PUB prn2(val) | dig
    dig := 48 + (val // 10)
    val := val/10
    if val > 0
        prn2(val)
    text.putc(pos++, dig)

PUB prn(val)
    text.putc(pos++, " ")
    if val < 0
        text.putc(pos++, "-")
        val := 0 - val
    prn2(val)

PUB putn(r, c, val)
    pos := r * termCols + c
    prn(val)

'' Write a string into the screen
PUB puts(row, col, str) | x, ptr
    ptr := (row * termCols) + col
    repeat x from 0 to STRSIZE(str)-1
        text.putc(ptr++, BYTE[str+x])


'' Process next byte from our host port
PUB testPutAt(row, col, c)
    ' Direct display-memory write used by the local geometry test.
    ' Does not advance the terminal cursor, wrap, or invoke scroll logic.
    if (row => 1) AND (row =< termRows) AND (col => 1) AND (col =< termCols)
        text.putc(((row - 1) * termCols) + (col - 1), c)

PUB singleSerial0(c)
    case state

    ' State 0: ready for new data to display or start of escape sequence
     0:
        ' Assume high bit chars are alternate character set
        '  output, and make them consume a space
        if c > 127
            c := $20

        ' Printing chars; translate DEC Special Graphics when G0 is selected
        if c => 32
            if g0graphics
                c := mapG0(c)
            simplec(c)
            text.setCursorPos(pos)
            return

        ' Escape sequence started
        if c == 27
            state := 1
            return

        ' CR
        if c == 13
            pos := pos - (pos // termCols)
            text.setCursorPos(pos)
            return

        ' LF
        if c == 10
            if inReg
                pos += termCols
                if pos => regBot
                    scrollUp
                    pos -= termCols
            else
                pos += termCols
                if pos => termChars
                    pos -= termCols
            text.setCursorPos(pos)
            return

        ' Tab
        if c == 9
            ' Advance to next tab stop
            pos += (8 - (pos // 8))

            ' Scroll when tab to new line
            if pos => termChars
                pos := termLastLine
                text.delLine(0)
            text.setCursorPos(pos) 
            return

        ' Backspace
        if c == 8
            if pos > 0
                pos -= 1
            text.setCursorPos(pos) 
            return

    ' State 1: ESC received, ready for escape sequence
     1:
        case c

         ' ESC-[, start of extended ANSI style arguments
         "[":
            a0 := a1 := -1
            state := 2
            return

         ' ESC-P, cursor down one line
         "P":
            pos += termCols
            if pos => termChars
                pos -= termCols

         ' ESC-K, cursor left one position
         "K":
            if pos > 0
                pos -= 1

         ' ESC-H, cursor up one line
         "H":
            pos -= termCols
            if pos < 0
                pos += termCols

         ' ESC-D, scroll one line
         "D":
            if inReg
                scrollUp

         ' ESC-M, scroll backward
         "M":
            if inReg
                scrollDown

         ' ESC-G, cursor home
         "G":
            pos := 0

         ' ESC-(, designate G0 character set
         "(":
            state := 5
            return

        ' Escape sequence done, reset state machine
        state := 0
        text.setCursorPos(pos) 
        return

    ' State 2: ESC-[, start decoding first numeric arg
     2:
        ' Digits, assemble value
        if (c => "0") AND (c =< "9")
            if a0 == -1
                a0 := c - "0"
            else
                a0 := (a0*10) + (c - "0")
            return

        ' Semicolon, advance to arg1
        if c == ";"
            state := 3
            return

        ' End of input sequence
        ansi(c)
        text.setCursorPos(pos) 
        return

    ' State 3: ESC-[<digits>;, start decoding second numeric arg
     3:
        ' Digits, assemble value
        if (c => "0") AND (c =< "9")
            if a1 == -1
                a1 := c - "0"
            else
                a1 := (a1*10) + (c - "0")
            return

        ' Semicolon, ignore subsequent args
        if c == ";"
            state := 4
            return

        ' End of sequence
        ansi(c)
        text.setCursorPos(pos) 
        return

    ' State 4: ESC-[<digits>;<digits>;...  Ignore subsequent args
     4:
        if (c => "0") AND (c =< "9")
            return
        if c == ";"
            return
        ansi(c)
        text.setCursorPos(pos) 
        return

    ' State 5: ESC-(, designate G0 character set
    '   ESC ( 0 = DEC Special Graphics
    '   ESC ( B = United States ASCII (and any other designator falls back to ASCII)
     5:
        if c == "0"
            g0graphics := 1
        else
            g0graphics := 0
        state := 0
        text.setCursorPos(pos) 
        return
    return


'' Map the VT100 DEC Special Graphics line-drawing characters onto the
'' control-code glyph slots already present in the Parallax 8x12 VGA font.
'' Unsupported DEC graphics characters are left unchanged.
''
'' VT100 names:  j=LR, k=UR, l=UL, m=LL, n=cross, q=horizontal,
''               t=left tee, u=right tee, v=bottom tee, w=top tee, x=vertical.
'' The scan-line characters o/p/r/s use the available horizontal glyph as a
'' practical approximation; q is the native center scan line.
PRI mapG0(c) : mapped
    mapped := c
    case c
        "j": mapped := $0D        ' lower-right corner
        "k": mapped := $0B        ' upper-right corner
        "l": mapped := $0A        ' upper-left corner
        "m": mapped := $0C        ' lower-left corner
        "n": mapped := $14        ' crossing
        "o": mapped := $0E        ' scan line 1 (approx.)
        "p": mapped := $0E        ' scan line 3 (approx.)
        "q": mapped := $0E        ' horizontal / scan line 5
        "r": mapped := $0E        ' scan line 7 (approx.)
        "s": mapped := $0E        ' scan line 9 (approx.)
        "t": mapped := $12        ' left tee
        "u": mapped := $13        ' right tee
        "v": mapped := $11        ' bottom tee
        "w": mapped := $10        ' top tee
        "x": mapped := $0F        ' vertical line

'' Set invert video based on control code
PRI setInv(c)
    if c == 1
        text.setInv(1)
    else
        text.setInv(0)

'' Tell if current position is within scroll region
PRI inReg : answer
    answer := (pos => regTop) AND (pos < regBot)

'' Scroll the contents of the scroll region upward
''  (i.e., add a new blank line at the bottom of the region)
PRI scrollUp
    text.delLine(regTop)
    if regBot < termChars
        text.insLine(regBot)

'' Scroll downward (new blank line at top)
PRI scrollDown
    if regBot < termChars
        text.delLine(regBot)
    text.insLine(regTop)

'' Take action for ANSI-style sequence
PRI ansi(c) | x, defVal

    ' Always reset input state machine at end of sequence
    state := 0

    ' Map args to appropriate default
    ' Most get a default argument of 1, a few 0.
    if (c <> "r") AND (c <> "J") AND (c <> "m") AND (c <> "K")
        if a0 == -1
            a0 := 1
        if a1 == -1
            a1 := 1

    case c

     "@":       ' Insert char(s)
        repeat while a0-- > 0
            text.insChar(pos)

     "b":       ' Repeat last char
        repeat while a0-- > 0
            simplec(lastc)

     "d":       ' Vertical position absolute
        if (a0 < 1) OR (a0 > termRows)
            a0 := termRows
        pos := ((a0-1) * termCols) + (pos // termCols)

     "m":       ' Set character enhancements
        setInv(a0)
        if a1 <> -1
            setInv(a1)

     "r":       ' Set scroll region
        ' TBD is to change all the scroll code to check the region

        ' Bound param to screen geometry
        if a0 < 1
            a0 := 1
        elseif a0 > termRows
            a0 := termRows
        if a1 < 1
            a1 := 1
        elseif a1 > termRows
            a1 := termRows
        if a1 < a0
            a1 := a0

        ' Set region; regTop is first location in the scroll region;
        '  regBot is first location beyond end of scroll region.
        regTop := (a0-1) * termCols
        regBot := a1 * termCols

        ' This op seems to implicitly home the cursor...
        pos := 0

     "A":       ' Move cursor up line(s)
        repeat while a0-- > 0
            pos -= termCols
            if pos < 0
                pos += termCols
                return

     "B":       ' Move cursor down line(s)
        repeat while a0-- > 0
            pos += termCols
            if pos => termChars
                pos -= termCols
                return

     "C":       ' Move cursor right
        repeat while a0-- > 0
            pos += 1
            if pos => termChars
                pos -= 1
                return

     "D":       ' Move cursor left
        repeat while a0-- > 0
            pos -= 1
            if pos < 0
                pos := 0
                return

     "G":       ' Horizontal position absolute
        if (a0 < 1) OR (a0 > termCols)
            a0 := termCols
        pos := (pos - (pos // termCols)) + (a0-1)

     "H":       ' Set cursor position (CUP/HVP)
        if a0 < 1
            a0 := 1
        elseif a0 > termRows
            a0 := termRows
        if a1 < 1
            a1 := 1
        elseif a1 > termCols
            a1 := termCols
        pos := (termCols * (a0-1)) + (a1 - 1)

     "J":       ' Clear screen/EOS
        ' Erase to top of screen
        if a0 == 1
            text.clBOL(pos)
            x := pos - termCols
            x -= x // termCols
            repeat while x => 0
                text.clEOL(x)
                x -= termCols
            return

        ' Erase whole screen and home cursor
        if a0 == 2
            pos := 0

        ' Clear from current position to end of screen
        text.clEOL(pos)
        x := pos + termCols
        x -= (x // termCols)
        repeat while x < termChars
            text.clEOL(x)
            x += termCols

     "K":       ' Clear parts of line
        if a0 == -1             ' No arg, to end of line
            text.clEOL(pos)
        elseif a0 == 1          ' 1 == from beginning to position
            text.clBOL(pos)
        else                    ' 2 == clear whole line
            text.clEOL(pos - (pos // termCols))


     "L":       ' Insert line(s)
        if inReg
            repeat while a0-- > 0
                if regBot < termChars
                    text.delLine(regBot)
                text.insLine(pos)

     "M":       ' Delete line(s)
        if inReg
            repeat while a0-- > 0
                text.delLine(pos)
                if regBot < termChars
                    text.insLine(regBot)

     "P":       ' Delete char(s)
        repeat while a0--
            text.delChar(pos)

'' Put a single printing char onto the screen
PRI simplec(c)
    text.putc(pos++, lastc := c)

    ' If just advanced beyond end of scroll region, scroll
    if pos == regBot
        scrollUp
        pos -= termCols

    ' If beyond scroll region & walk off screen, wrap
    '  back around to column 0
    elseif pos == termChars
        pos := termLastLine
