{{
 Persistent display settings for the S-100 Propeller Console I/O board.

 Uses the Propeller P1 boot EEPROM on P28/P29:
   P28 = SCL
   P29 = SDA

 A versioned settings record is stored at $7FF0, the last 16-byte region
 of a standard 32K (24LC256-compatible) Propeller boot EEPROM.

 IMPORTANT: Uploading a new program to EEPROM/Flash writes the boot image
 again, so saved settings should be expected to reset after reflashing.
 They will be written again the next time a display setting is changed.
}}

CON
    EEPROM_SCL      = 28
    EEPROM_SDA      = 29
    EEPROM_WRITE    = $A0
    EEPROM_READ     = $A1

    SETTINGS_ADDR   = $7FF0
    RECORD_SIZE_V1  = 8
    RECORD_SIZE_V2  = 9
    RECORD_SIZE     = RECORD_SIZE_V2

    MAGIC0          = $43        ' C
    MAGIC1          = $49        ' I
    FORMAT_VERSION_V1 = 1
    FORMAT_VERSION    = 2
    TRAILER         = $A5

VAR
    byte rec[RECORD_SIZE]

PUB load(pMode, pForeground, pBackground, pFont) : valid | sum
    valid := 0

    ' Read enough bytes for the current record.  Old V29.8 records occupy the
    ' first eight bytes and remain readable.
    if readBlock(SETTINGS_ADDR, @rec, RECORD_SIZE) == 0
        return

    if rec[0] <> MAGIC0
        return
    if rec[1] <> MAGIC1
        return

    if rec[2] == FORMAT_VERSION_V1
        ' V1 layout: magic,version,mode,fg,bg,trailer,checksum.
        if rec[6] <> TRAILER
            return
        sum := (rec[0] + rec[1] + rec[2] + rec[3] + rec[4] + rec[5] + rec[6]) & $FF
        if rec[7] <> sum
            return
        if rec[3] > 2
            return
        if (rec[4] & $03) <> 0
            return
        if (rec[5] & $03) <> 0
            return

        byte[pMode] := rec[3]
        byte[pForeground] := rec[4]
        byte[pBackground] := rec[5]
        byte[pFont] := 0                  ' Default font for pre-V29.9 settings
        valid := 1
        return

    if rec[2] <> FORMAT_VERSION
        return
    if rec[7] <> TRAILER
        return

    sum := (rec[0] + rec[1] + rec[2] + rec[3] + rec[4] + rec[5] + rec[6] + rec[7]) & $FF
    if rec[8] <> sum
        return

    if rec[3] > 2
        return
    if rec[6] > 2
        return

    ' VGA color bytes use only bits 7..2 (%RRGGBB00).
    if (rec[4] & $03) <> 0
        return
    if (rec[5] & $03) <> 0
        return

    byte[pMode] := rec[3]
    byte[pForeground] := rec[4]
    byte[pBackground] := rec[5]
    byte[pFont] := rec[6]
    valid := 1

PUB save(mode, foreground, background, font) : okay
    rec[0] := MAGIC0
    rec[1] := MAGIC1
    rec[2] := FORMAT_VERSION
    rec[3] := mode
    rec[4] := foreground & $FC
    rec[5] := background & $FC
    rec[6] := font
    rec[7] := TRAILER
    rec[8] := (rec[0] + rec[1] + rec[2] + rec[3] + rec[4] + rec[5] + rec[6] + rec[7]) & $FF

    okay := writeBlock(SETTINGS_ADDR, @rec, RECORD_SIZE)

PRI readBlock(address, pData, count) : okay | i
    releaseBus
    i2cStart

    if i2cWrite(EEPROM_WRITE) == 0
        i2cStop
        return 0
    if i2cWrite((address >> 8) & $FF) == 0
        i2cStop
        return 0
    if i2cWrite(address & $FF) == 0
        i2cStop
        return 0

    i2cStart
    if i2cWrite(EEPROM_READ) == 0
        i2cStop
        return 0

    repeat i from 0 to count - 1
        if i == count - 1
            byte[pData + i] := i2cRead(0)      ' NAK after final byte
        else
            byte[pData + i] := i2cRead(1)      ' ACK, more bytes follow

    i2cStop
    okay := 1

PRI writeBlock(address, pData, count) : okay | i
    ' SETTINGS_ADDR is chosen so this small record never crosses an EEPROM
    ' page boundary.  The whole record therefore costs one EEPROM write cycle.
    releaseBus
    i2cStart

    if i2cWrite(EEPROM_WRITE) == 0
        i2cStop
        return 0
    if i2cWrite((address >> 8) & $FF) == 0
        i2cStop
        return 0
    if i2cWrite(address & $FF) == 0
        i2cStop
        return 0

    repeat i from 0 to count - 1
        if i2cWrite(byte[pData + i]) == 0
            i2cStop
            return 0

    i2cStop

    ' 24LC-style EEPROMs need a few milliseconds to complete an internal
    ' page-write cycle.  Ten milliseconds is intentionally conservative.
    waitcnt(cnt + clkfreq / 100)
    okay := 1

PRI releaseBus
    outa[EEPROM_SCL] := 0
    outa[EEPROM_SDA] := 0
    dira[EEPROM_SCL] := 0
    dira[EEPROM_SDA] := 0
    i2cDelay

PRI i2cStart
    sdaHigh
    sclHigh
    sdaLow
    sclLow

PRI i2cStop
    sdaLow
    sclHigh
    sdaHigh

PRI i2cWrite(value) : ack | i
    repeat i from 0 to 7
        if (value & $80) <> 0
            sdaHigh
        else
            sdaLow

        sclHigh
        sclLow
        value <<= 1

    ' Release SDA for the EEPROM's ACK bit.
    sdaHigh
    sclHigh
    ack := (ina[EEPROM_SDA] == 0)
    sclLow

PRI i2cRead(sendAck) : value | i
    value := 0
    sdaHigh

    repeat i from 0 to 7
        value <<= 1
        sclHigh
        if ina[EEPROM_SDA]
            value |= 1
        sclLow

    if sendAck
        sdaLow
    else
        sdaHigh

    sclHigh
    sclLow
    sdaHigh

PRI sclHigh
    dira[EEPROM_SCL] := 0
    i2cDelay

PRI sclLow
    outa[EEPROM_SCL] := 0
    dira[EEPROM_SCL] := 1
    i2cDelay

PRI sdaHigh
    dira[EEPROM_SDA] := 0
    i2cDelay

PRI sdaLow
    outa[EEPROM_SDA] := 0
    dira[EEPROM_SDA] := 1
    i2cDelay

PRI i2cDelay
    ' IMPORTANT: In Spin, WAITCNT needs a comfortably future target and CNT
    ' should be evaluated last.  A tiny 'cnt + 400' delay can miss its target
    ' while the interpreter is evaluating/dispatching the statement, causing
    ' an almost full 32-bit counter wrap wait.  100 us is deliberately slow
    ' for I2C but completely safe for this tiny settings record.
    waitcnt(clkfreq / 10_000 + cnt)
