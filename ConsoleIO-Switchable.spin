''       S100 ConsoleIO board driver
''       John Monahan  (monahan@vitasoft.org)   5/25/2011
''

''      V28.0    5/25/2011      Corrected problem with DEL key
''      V28.1     8/2/2011      Added Int vector for key press input 
''      V28.2   10/18/2011      Fixed recognition of CTRL & ALT keys

''      Pete Clark (peclark@gmail.com) 8/13/2026 
''      Added ability to switch resolutions and foreground and background colors, choice is stored in EEPROM and
''      remembered across power cycles
''
''      Ctrl+Alt+F1/F2/F3 select resolution.
''      Ctrl+Alt+F4 cycles foreground color.
''      Ctrl+Alt+F5 cycles background color.
''      Ctrl+Alt+F6 swaps foreground/background.
''      Ctrl+Alt+F7 resets to white on black.
''      Ctrl+Alt+F8 opens local display setup/status screen.
''
''      V29.0    8/13/2026      Added switchable VGA modes: Ctrl+Alt+F1/F2/F3
''      V29.1    8/13/2026      Added runtime foreground/background color controls
''      V29.2    8/13/2026      Remember VGA resolution/colors in Propeller boot EEPROM
''      V29.3    8/13/2026      Fix EEPROM I2C WAITCNT timing for Spin interpreter
''      V29.4    8/14/2026      Show raw PS/2 Set-2 scan code in first pair of HEX displays
''      V29.5    8/14/2026      Add VT100 ESC ( 0 DEC Special Graphics line-drawing support
''      V29.6    8/14/2026      Full-screen native geometry baseline; correct ANSI scroll-region row bounds
''      V29.7    8/14/2026      Single runtime VGA renderer; geometry synchronization hardening
''      V29.8    8/14/2026      Add Ctrl+Alt+F8 local display-configuration UI
''      V29.9    8/14/2026      Add selectable/persistent Default, VT100-style, and IBM PC-style 8x12 fonts
''      V29.11   8/14/2026      Source-guided DEC VT220 and IBM PC VGA alternate fonts
''      V29.13   8/14/2026      Add display/geometry calibration test screen (D in setup)
''      V29.14   8/14/2026      Prevent geometry test bottom-right corner from triggering terminal scroll
''      V29.16    9/1/2026      Add 128-byte host-output FIFO and second Spin cog so S-100 character
''                              acceptance overlaps VT100 parsing/rendering. Direct 1000-line benchmark
''                              improved from ~32 sec to ~23 sec (~28% less time / ~39% more throughput).
''                              CP/M BDOS benchmark remains ~46-47 sec because BDOS becomes the bottleneck.

''      Keyboard HEX displays:
''      Left pair  = raw PS/2 Set-2 make scan code
''      Right pair = translated character/code sent to the S-100 host

    
CON
    _clkmode = xtal1 + pll16x
    _xinfreq = 5_000_000

    '' VGA driver: video output pin
    video = 16

    '' RS-232 driver values:  rx and tx lines
    r0 = 31
    t0 = 30

    '' Keyboard clock and data
    kbd = 14
    kbc = 15

    BS = 8
    LF = 10
    CR = 13
    ESC = 27

    DEFAULT_MODE = 2
    DEFAULT_FG   = $FC
    DEFAULT_BG   = $00
    DEFAULT_FONT = 0
  
VAR

  word  keyboard_char                    'Must be word because CTRL,ALT etc info is in high byte
  byte  keyboard_status
  byte  ch
  long  scankey
  byte  startupMode
  byte  startupFg
  byte  startupBg
  byte  startupFont
  byte  savedMode
  byte  savedFg
  byte  savedBg
  byte  savedFont
 
OBJ
    te:         "VT100_Emulator-Switchable" ' Runtime VGA geometry + V29.16 buffered host output
    kb:         "Keyboard"              ' Keyboard driver
    ser0:       "FullDuplexSerial"      ' Full Duplex Serial Controller(s)
    prefs:      "EEPROM_Settings"       ' Persistent display mode/color settings



PUB main

    init_devices                                        ' One-time setup of Serial, VGA and Keyboard    

    loadDisplaySettings                                 ' Read saved mode/colors/font, or use defaults
    te.start(video, startupMode, startupFg, startupBg, startupFont) ' Start VGA with saved/default settings
    te.init                                             ' Initialize terminal emulator for active geometry
    
    dira[7..0]~~                                        'Set P7-P0 to output

    dira[8]~~                                           'Console OUT Busy while receiving/queueing host data, always out
    outa[8] := 0                                        'nothing right now 

    dira[9]~                                            'DATA_IN_BUSY is read via this pin, alwauys in
    
    dira[10]~~                                          'Keyboard character available status bit, always out
    outa[10] := 0                                       'nothing right now

    dira[11]~                                           'DATA_OUT_BUSY is read via this pin, alwauys in

    dira[12]~~                                          'Pin 12 for interrupt vector to S-100 bus -  output
    outa[12] := 1                                       'Will be edge triggered on S-100 bus for MS-DOS/BIOS Monitor. Off initially

    dira[13]~~                                          'Pin for buzzer/bell - output
    outa[13] := 1

 
    dira[24]~~                                          'To latch U47
    outa[24] := 1                                       'Nothing initially
    dira[25]~~                                          'To latch U46
    outa[25] := 1                                       'Nothing initially

    dira[26]~~                                          'Set P26 to output for HEX display (keyboard key code)
    outa[26] := 1                                       'Nothing to latch right now
    dira[27]~~                                          'Set P27 to output for HEX display (keyboard ASCII translated key)
    outa[27] := 1                                       'no strobe or latch yet
                                                         
                                                        'P14 & P15 are for keyboard data & clock signals
 


    
    keyboard_status := 0                                'Flag as nothing there
    
    repeat

             if keyboard_status == 0                            'If nothing so far
                
                 keyboard_char := kb.key                        'Check if something in que (Note word returned)
                 scankey := kb.scancode                          'Raw PS/2 Set-2 scan byte matched to this queued key

                 if displayHotkey(keyboard_char)                   'Consume local VGA mode/color hotkeys
                     keyboard_char := 0                             'Do not pass them to the S-100 host

                                                                                                                                                  
                 if keyboard_char.byte[0] <> 0                  'non-zero means we have a character

                                    
                         keyboard_status := $ff                  'set flag we have a character

                         if keyboard_char.byte[0] == $c8         'Backspace keyboard key
                             keyboard_char.byte[0] := $08
                             
                         if keyboard_char.byte[0] == $C9         'Delete Keyboard key (on Number Pad with NUM Lock Off) 
                             keyboard_char.byte[0] := $7F
                                                                 '(Note you can play around here adding Characters or whole strings for the Function keys etc.)

                         if keyboard_char.byte[0] == $CB         'ESC key
                                keyboard_char.byte[0] := $1B

                                               
                         if keyboard_char.byte[0] == $DC          'Print Scr key   ---> to the IBM BIOS as $1CH (^\)  
                             keyboard_char.byte[0] := $1C

                                                                   'Check for Ctrl+ALT+ DEL ---> to the IBM BIOS as $1DH (^]
                         if((keyboard_char.byte[1] == $06) & (keyboard_char.byte[0] == $7F)) '
                                                                                              
                                 keyboard_char.byte[0] := $1D      'Check for Alt in Ctrl/Alt/Del key will be sent to the IBM BIOS

                                                                    
                         if keyboard_char.byte[1] == $02           'Check for Crtl (only)                  

                             if keyboard_char.byte[0] == $DF       'Check for NUM_LOCK  (On PC This pauses the computer)
                                 keyboard_char.byte[0] := $1E      'Ctrl/BREAK = Ctrl+NUM-LOCK key will be sent to the IBM BIOS as $1EH (^^)      
                        
                             else
                                    keyboard_char.byte[0] &= $1F    'If so convert everything to ^ characters


                         if keyboard_char.byte[1] == $04            'Is the ALT key to be recognized
                                 keyboard_char.byte[0] |= $80       'If so set bit 7 for my PC-BIOS. (This is only relevent for the IBM-PC BIOS)
                                 
                                                        

                         outa[7..0] := scankey.byte[0]           'Left HEX pair: raw PS/2 Set-2 scan code
                         outa[26] := 0                            'Pulse line to latch data into HEX display
                         outa[26] := 1       
                                
                         outa[7..0] := keyboard_char.byte[0]      'Update the HEX display
                         outa[27] := 0                            'Pulse line to latch data into HEX display
                         outa[27] := 1
                         
                         outa[24] := 0                            'Also latch data into U47
                         outa[24] := 1

                                               
                         outa[10] := 1                  'Only then do we flag S-100 bus as something there (bit 1 of port 14H = 1)
                                                        'This is a little subtle. The strobe pulse from P24 will clock the 74LS74
                                                        'so StatusInBusy goes high. This will go to pin 2 of U39A. However only when
                                                        'P10 goes high on pin 1 of U39A does the status appear on the S100 bus indicating
                                                        'the board has a new keyboard character to be read. However the instant the S-100
                                                        'bus reads the data from U47 its pin 1 immediatly resets the 74LS74 removing the character available
                                                        'status bit from the S-100 bus.  The reason we have the "double" requirement for a
                                                        'status bit is because the p24 pulse (using Spin) is too long, causing the S-100 bus
                                                        'with a fast (eq 10Mhz Z80) to pick up two characters instead of one.

                         outa[12] := 0                  'Now pulse the S-100 vector Int line (used by MS-DOS BIOS)
                         waitcnt(clkfreq / 10 + cnt)    'wait for .1 seconds (100 ms) just in case -- though the 8259A should be edge triggered
                         outa[12] := 1                  'This way we will see the Int LED actully flash on the board.
                         
                                                         
             if keyboard_status == $ff                  'If we have a keyboard character
                                         
                 if ina[9] == %0                        'P9 Low, so character has now been read by S-100 bus (INPUT_ENABLE* went low resetting 7474, DATA_IN_BUSY)

                       outa[10] := 0                    'Flag S-100 bus no more characters available to be read
                       
                       keyboard_status := 0             'For next time     
                       
                      
          
            if ina[11] == %1                            'Is there an S-100 bus character WRITE request (P11, LATCHED_OUTPUT_ENABLE high)

                  outa[8] := 1                          'Raise Console Busy while this host byte is captured and queued.
                                                        'V29.16 releases Busy after enqueueing; rendering continues concurrently.

                  dira[7..0]~                           'Set P7-P0 to INPUT mode

                  outa[25] := 0                         'Lower 74LS373 OE pin (to place data on P0-P7 lines)
                                                        'Note this will also clear U44, LATCHED_OUTPUT_ENABLE, but because P8 is high/busy bit 2
                                                        'back to S-100 system is still low. This is necessary because the pulse signal from P25
                                                        'is long enough that a 10MHz Z80 can squeeze in another invalid console busy status bit check
                                                        
                  ch := ina[7..0]                       'Get the data
                  outa[25] := 1                         'Raise OE pine when done.   

                         
                      case ch
                                
                                $07:                                            'If Bell (07H) ring buzzer
                                        outa[13] :=  0
                                        waitcnt(clkfreq / 10 + cnt)             'wait for .1 seconds (100 ms)
                                        outa[13] := 1

                                $1A:                                            'For compatability with my SD Systems 8024 Video Board
                                   te.singleSerial0(27)                         '1AH clear Screen
                                   te.singleSerial0("[")                        'First home cursor
                                   te.singleSerial0("H")
                                   
                                   te.singleSerial0(27)                         'Then clear to EOS
                                   te.singleSerial0("[")                        
                                   te.singleSerial0("J")

                                $1C:                                             'For compatability with my SD Systems 8024 Video Board
                                   te.singleSerial0(27)                          '1CH clear from cursor position to EOL
                                   te.singleSerial0("[")                         
                                   te.singleSerial0("K")

                                $11:                                             'For compatability with my SD Systems 8024 Video Board
                                   te.singleSerial0(27)                          '11H turn off screen enhancements
                                   te.singleSerial0("[")                         
                                   te.singleSerial0("m")

                                $1E:                                             'For compatability with my SD Systems 8024 Video Board
                                   te.singleSerial0(27)                          '1eH home cursor
                                   te.singleSerial0("[")
                                   te.singleSerial0("H")
                                 
                                OTHER:
                                   te.singleSerial0(ch)                         'V29.16: enqueue ordinary host output for renderer cog
                                         
                                                                          
                  dira[7..0]~~                                                  'Set P7-P0 back to OUTPUT
                        
                  outa[8] := 0                                                  'Byte is queued; host may send the next character.
                                                        'VT100 parsing/rendering may still be running in the output cog.
                   
                                                                             


'' Local display hotkeys. Keyboard.spin returns +$200 for Ctrl and +$400 for Alt,
'' so Ctrl+Alt appears as $06 in the high byte.
''
'' Ctrl+Alt+F1/F2/F3 select resolution.
'' Ctrl+Alt+F4 cycles foreground color.
'' Ctrl+Alt+F5 cycles background color.
'' Ctrl+Alt+F6 swaps foreground/background.
'' Ctrl+Alt+F7 resets to white on black.
'' Ctrl+Alt+F8 opens the local display configuration screen.
PRI displayHotkey(key) : handled

    handled := 0
    if key.byte[1] == $06
        case key.byte[0]
            $D0:
                if te.setMode(0)               ' 640x480, 80x40
                    rememberDisplaySettings
                handled := 1
            $D1:
                if te.setMode(1)               ' 800x600, 100x50
                    rememberDisplaySettings
                handled := 1
            $D2:
                if te.setMode(2)               ' 1024x768, 128x64
                    rememberDisplaySettings
                handled := 1
            $D3:
                te.cycleForeground             ' F4
                rememberDisplaySettings
                handled := 1
            $D4:
                te.cycleBackground             ' F5
                rememberDisplaySettings
                handled := 1
            $D5:
                te.swapColors                  ' F6
                rememberDisplaySettings
                handled := 1
            $D6:
                te.resetColors                 ' F7
                rememberDisplaySettings
                handled := 1
            $D7:
                configurationMenu              ' F8
                handled := 1


'' Local setup/status UI.  Changes are previewed immediately.  S saves the
'' selected mode/colors/font using the versioned EEPROM record; X cancels and restores
'' the exact settings that were active when setup was entered.
PRI configurationMenu | oldMode, oldFg, oldBg, oldFont, key, done, saveIt
    oldMode := te.getMode
    oldFg := te.getForeground
    oldBg := te.getBackground
    oldFont := te.getFont
    done := 0
    saveIt := 0

    repeat while done == 0
        drawConfigurationMenu
        key := waitLocalKey

        ' Accept either upper- or lower-case menu letters.
        if (key => "a") and (key =< "z")
            key -= 32

        case key
            "1":
                te.setMode(0)
            "2":
                te.setMode(1)
            "3":
                te.setMode(2)
            "F":
                te.cycleForeground
            "B":
                te.cycleBackground
            "W":
                te.swapColors
            "T":
                te.cycleFont
            "R":
                te.resetColors
            "D":
                displayTest
            "S":
                saveIt := 1
                done := 1
            "X", ESC:
                done := 1

    if saveIt
        rememberDisplaySettings
        te.init
        localString(string("Console I/O configuration saved."))
        localCRLF
        localString(string("Resolution/geometry, font, and colors will be restored at power-up."))
    else
        if te.getMode <> oldMode
            te.setMode(oldMode)
        te.setFont(oldFont)
        te.setColors(oldFg, oldBg)
        te.init
        localString(string("Console I/O configuration unchanged."))

    localCRLF
    localString(string("Press any key to return to the host."))
    waitLocalKey
    te.init

PRI drawConfigurationMenu | mode
    te.init

    localString(string("S-100 CONSOLE I/O SETUP"))
    localCRLF
    localString(string("======================="))
    localCRLF
    localCRLF

    mode := te.getMode
    localString(string("Video mode / native terminal geometry:"))
    localCRLF
    if mode == 0
        localString(string("  > 1.  640 x 480     80 columns x 40 lines"))
    else
        localString(string("    1.  640 x 480     80 columns x 40 lines"))
    localCRLF
    if mode == 1
        localString(string("  > 2.  800 x 600    100 columns x 50 lines"))
    else
        localString(string("    2.  800 x 600    100 columns x 50 lines"))
    localCRLF
    if mode == 2
        localString(string("  > 3. 1024 x 768    128 columns x 64 lines"))
    else
        localString(string("    3. 1024 x 768    128 columns x 64 lines"))
    localCRLF
    localCRLF

    localString(string("Font:       "))
    localString(fontName(te.getFont))
    localCRLF
    localCRLF

    localString(string("Foreground: "))
    localString(colorName(te.getForeground))
    localString(string("  ($"))
    localHexByte(te.getForeground)
    localString(string(")"))
    localCRLF

    localString(string("Background: "))
    localString(colorName(te.getBackground))
    localString(string("  ($"))
    localHexByte(te.getBackground)
    localString(string(")"))
    localCRLF
    localCRLF

    localString(string("Choose an option below by pressing the corresponding key:"))
    localCRLF
    localCRLF
    localString(string("1/2/3  Select video mode"))
    localCRLF
    localString(string("T      Select font (live preview):"))
    localCRLF
    localString(string("       Default / DEC VT220 / IBM PC VGA"))
    localCRLF
    localString(string("F      Next foreground color"))
    localCRLF
    localString(string("B      Next background color"))
    localCRLF
    localString(string("W      Swap foreground/background"))
    localCRLF
    localString(string("R      Reset to white on black"))
    localCRLF
    localString(string("D      Display / geometry test"))
    localCRLF
    localString(string("S      Save and exit"))
    localCRLF
    localString(string("X/ESC  Cancel and restore previous settings"))
    localCRLF

PRI displayTest | cols, rows, midCol, midRow, i, mode, testFg, testBg
    ' Temporary display/calibration screen for the currently previewed setup.
    ' Nothing here writes EEPROM or changes the selected mode/font/colors.
    mode := te.getMode
    case mode
        0:
            cols := 80
            rows := 40
        1:
            cols := 100
            rows := 50
        OTHER:
            cols := 128
            rows := 64

    midCol := (cols + 1) / 2
    midRow := (rows + 1) / 2
    testFg := te.getForeground
    testBg := te.getBackground

    te.init

    ' Exact outer edge of the usable character matrix.
    localGoto(1, 1)
    te.singleSerial0("+")
    repeat i from 2 to cols - 1
        te.singleSerial0("-")
    te.singleSerial0("+")

    repeat i from 2 to rows - 1
        localGoto(i, 1)
        te.singleSerial0("|")
        localGoto(i, cols)
        te.singleSerial0("|")

    localGoto(rows, 1)
    te.singleSerial0("+")
    repeat i from 2 to cols - 1
        te.singleSerial0("-")
    ' Do not send the final bottom-right cell through normal terminal output:
    ' advancing past the last screen cell would invoke the terminal's scroll logic.
    te.testPutAt(rows, cols, "+")

    ' Center crosshair.  Text below is written afterward so labels stay legible.
    repeat i from 2 to cols - 1
        localGoto(midRow, i)
        te.singleSerial0("-")
    repeat i from 2 to rows - 1
        localGoto(i, midCol)
        te.singleSerial0("|")
    localGoto(midRow, midCol)
    te.singleSerial0("+")

    ' Horizontal ruler.  Labels mark real one-based terminal columns.
    localGoto(2, 3)
    localString(string("COL"))
    repeat i from 10 to cols step 10
        if i < cols - 2
            localGoto(2, i)
            localDec(i)
            localGoto(3, i)
            te.singleSerial0("|")

    ' Vertical ruler, every five terminal rows.
    repeat i from 5 to rows - 5 step 5
        localGoto(i, 2)
        localDec(i)
        localGoto(i, 5)
        te.singleSerial0("-")

    ' Four unmistakable near-corner markers make clipping/overscan obvious.
    localGoto(3, 2)
    localString(string("TL"))
    localGoto(3, cols - 3)
    localString(string("TR"))
    localGoto(rows - 2, 2)
    localString(string("BL"))
    localGoto(rows - 2, cols - 3)
    localString(string("BR"))

    ' Identification and geometry.
    localGoto(5, 8)
    localString(string("S-100 CONSOLE I/O DISPLAY TEST"))
    localGoto(7, 8)
    localString(string("VGA: "))
    case mode
        0: localString(string("640 x 480"))
        1: localString(string("800 x 600"))
        OTHER: localString(string("1024 x 768"))
    localString(string("    TERMINAL: "))
    localDec(cols)
    localString(string(" x "))
    localDec(rows)
    localString(string("    CELL: 8 x 12"))

    localGoto(8, 8)
    localString(string("FONT: "))
    localString(fontName(te.getFont))
    localString(string("    FG: "))
    localString(colorName(te.getForeground))
    localString(string("    BG: "))
    localString(colorName(te.getBackground))

    ' Font and character-spacing samples.
    localGoto(10, 8)
    localString(string("ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    localGoto(11, 8)
    localString(string("abcdefghijklmnopqrstuvwxyz"))
    localGoto(12, 8)
    localString(string("0123456789  !@#$%^&*()  []{}<>?/\\"))

    localGoto(14, 8)
    localString(string("1234567890 1234567890 1234567890 1234567890"))
    localGoto(15, 8)
    localString(string("IIIIIIIIII WWWWWWWWWW MMMMMMMMMM .........."))

    ' Selected-color / inverse-video check using the terminal's actual attributes.
    localGoto(17, 8)
    localString(string("SELECTED COLORS:  NORMAL SAMPLE  "))
    localInverse(1)
    localString(string(" INVERSE SAMPLE "))
    localInverse(0)

    ' Text-mode color bars.  The VGA driver supports one color pair per row,
    ' so eight rows become useful calibration bands.  Inverse spaces make a
    ' solid block of the foreground color on black.
    localGoto(22, 8)
    localString(string("COLOR BARS"))
    localColorBand(23, $FC, string("WHITE"))
    localColorBand(24, $30, string("GREEN"))
    localColorBand(25, $E0, string("AMBER"))
    localColorBand(26, $3C, string("CYAN"))
    localColorBand(27, $F0, string("YELLOW"))
    localColorBand(28, $C0, string("RED"))
    localColorBand(29, $CC, string("MAGENTA"))
    localColorBand(30, $0C, string("BLUE"))

    ' Center marker label, without disturbing the crosshair outside the label.
    localGoto(midRow, midCol - 6)
    localString(string("[ CENTER ]"))

    ' Bottom status/prompt stays inside the exact outer border.
    localGoto(rows - 1, 7)
    localString(string("Any key returns to setup"))

    waitLocalKey
    te.setColors(testFg, testBg)
    te.init

PRI localColorBand(row, fg, labelPtr) | i
    te.setRowColors(row - 1, fg, $00)
    localGoto(row, 8)
    localInverse(1)
    repeat i from 1 to 18
        te.singleSerial0(" ")
    localInverse(0)
    te.singleSerial0(" ")
    localString(labelPtr)

PRI localGoto(row, col)
    te.singleSerial0(ESC)
    te.singleSerial0("[")
    localDec(row)
    te.singleSerial0(";")
    localDec(col)
    te.singleSerial0("H")

PRI localDec(value)
    if value => 100
        te.singleSerial0("0" + ((value / 100) // 10))
        te.singleSerial0("0" + ((value / 10) // 10))
    elseif value => 10
        te.singleSerial0("0" + ((value / 10) // 10))
    te.singleSerial0("0" + (value // 10))

PRI localInverse(enable)
    te.singleSerial0(ESC)
    te.singleSerial0("[")
    if enable
        te.singleSerial0("1")
    else
        te.singleSerial0("0")
    te.singleSerial0("m")

PRI waitLocalKey : key | raw
    repeat
        raw := kb.key
        if raw.byte[0] <> 0
            key := raw.byte[0]
            return

PRI localString(p) | c
    repeat while byte[p] <> 0
        c := byte[p++]
        te.singleSerial0(c)

PRI localCRLF
    te.singleSerial0(CR)
    te.singleSerial0(LF)

PRI localHexByte(value) | n
    n := (value >> 4) & $0F
    localHexNibble(n)
    n := value & $0F
    localHexNibble(n)

PRI localHexNibble(n)
    if n < 10
        te.singleSerial0("0" + n)
    else
        te.singleSerial0("A" + n - 10)

PRI fontName(value) : p
    case value
        0: p := string("Default")
        1: p := string("DEC VT220")
        2: p := string("IBM PC VGA")
        OTHER: p := string("Default")

PRI colorName(value) : p
    case value & $FC
        $FC: p := string("White")
        $30: p := string("Green")
        $E0: p := string("Amber")
        $3C: p := string("Cyan")
        $F0: p := string("Yellow")
        $C0: p := string("Red")
        $CC: p := string("Magenta")
        $0C: p := string("Blue")
        $A8: p := string("Gray")
        $00: p := string("Black")
        $04: p := string("Dark blue")
        $08: p := string("Medium blue")
        $10: p := string("Dark green")
        $14: p := string("Dark cyan")
        $40: p := string("Dark red")
        $44: p := string("Dark magenta")
        $54: p := string("Dark gray")
        OTHER: p := string("Custom")

PRI loadDisplaySettings
    startupMode := DEFAULT_MODE
    startupFg := DEFAULT_FG
    startupBg := DEFAULT_BG
    startupFont := DEFAULT_FONT

    ' If the record is absent/invalid, prefs.load leaves the defaults alone.
    prefs.load(@startupMode, @startupFg, @startupBg, @startupFont)

    savedMode := startupMode
    savedFg := startupFg
    savedBg := startupBg
    savedFont := startupFont

PRI rememberDisplaySettings | mode, fg, bg, font, changed
    mode := te.getMode
    fg := te.getForeground
    bg := te.getBackground
    font := te.getFont

    changed := 0
    if mode <> savedMode
        changed := 1
    if fg <> savedFg
        changed := 1
    if bg <> savedBg
        changed := 1
    if font <> savedFont
        changed := 1

    if changed
        if prefs.save(mode, fg, bg, font)
            savedMode := mode
            savedFg := fg
            savedBg := bg
            savedFont := font


'' Process bytes from our host port
PRI doSerial0 | c

    ' Consume bytes until FIFO is empty
    repeat
        c := ser0.rxcheck
        ser0.tx(c)

'' One-time initialization of terminal driver state
PRI init_devices

    ' Initialize RS-232 ports.  We'll shortly be restarting them
    '  after we choose a config
    ser0.start(r0, t0, 0, 9600)


    ' Start Keyboard Driver
    kb.start(kbd, kbc)
