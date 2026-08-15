{{
Object file:    FullDuplexSerial.spin
Version:        1.2.1
Date:           2006 - 2011
Author:         Chip Gracey, Jeff Martin, Daniel Harris
Company:        Parallax Semiconductor
Licensing:      MIT License - original Parallax Propeller library object.

This copy preserves the executable Spin/PASM source of Parallax FullDuplexSerial
v1.2.1. Documentation comments have been shortened only; executable code is
unchanged from the v1.2.1 library source.
}}

VAR
  long  cog

  ' 9 longs, MUST be contiguous
  long  rx_head
  long  rx_tail
  long  tx_head
  long  tx_tail
  long  rx_pin
  long  tx_pin
  long  rxtx_mode
  long  bit_ticks
  long  buffer_ptr

  byte  rx_buffer[16]
  byte  tx_buffer[16]

PUB Start(rxPin, txPin, mode, baudrate) : okay
  Stop
  longfill(@rx_head, 0, 4)
  longmove(@rx_pin, @rxpin, 3)
  bit_ticks := clkfreq / baudrate
  buffer_ptr := @rx_buffer
  okay := cog := cognew(@entry, @rx_head) + 1

PUB Stop
  if cog
    cogstop(cog~ - 1)
  longfill(@rx_head, 0, 9)

PUB RxFlush
  repeat while RxCheck => 0

PUB RxCheck : rxByte
  rxByte--
  if rx_tail <> rx_head
    rxByte := rx_buffer[rx_tail]
    rx_tail := (rx_tail + 1) & $F

PUB RxTime(ms) : rxByte | t
  t := cnt
  repeat until (rxByte := RxCheck) => 0 or (cnt - t) / (clkfreq / 1000) > ms

PUB Rx : rxByte
  repeat while (rxByte := RxCheck) < 0

PUB Tx(txByte)
  repeat until (tx_tail <> (tx_head + 1) & $F)
  tx_buffer[tx_head] := txByte
  tx_head := (tx_head + 1) & $F

  if rxtx_mode & %1000
    Rx

PUB Str(stringPtr)
  repeat strsize(stringPtr)
    Tx(byte[stringPtr++])

PUB Dec(value) | i, x
  x := value == NEGX
  if value < 0
    value := ||(value+x)
    Tx("-")

  i := 1_000_000_000
  repeat 10
    if value => i
      Tx(value / i + "0" + x*(i == 1))
      value //= i
      result~~
    elseif result or i == 1
      Tx("0")
    i /= 10

PUB Hex(value, digits)
  value <<= (8 - digits) << 2
  repeat digits
    Tx(lookupz((value <-= 4) & $F : "0".."9", "A".."F"))

PUB Bin(value, digits)
  value <<= 32 - digits
  repeat digits
    Tx((value <-= 1) & 1 + "0")

DAT
                        org

entry                   mov     t1,par
                        add     t1,#4 << 2

                        rdlong  t2,t1
                        mov     rxmask,#1
                        shl     rxmask,t2

                        add     t1,#4
                        rdlong  t2,t1
                        mov     txmask,#1
                        shl     txmask,t2

                        add     t1,#4
                        rdlong  rxtxmode,t1

                        add     t1,#4
                        rdlong  bitticks,t1

                        add     t1,#4
                        rdlong  rxbuff,t1
                        mov     txbuff,rxbuff
                        add     txbuff,#16

                        test    rxtxmode,#%100  wz
                        test    rxtxmode,#%010  wc
        if_z_ne_c       or      outa,txmask
        if_z            or      dira,txmask

                        mov     txcode,#transmit

receive                 jmpret  rxcode,txcode

                        test    rxtxmode,#%001  wz
                        test    rxmask,ina      wc
        if_z_eq_c       jmp     #receive

                        mov     rxbits,#9
                        mov     rxcnt,bitticks
                        shr     rxcnt,#1
                        add     rxcnt,cnt

:bit                    add     rxcnt,bitticks

:wait                   jmpret  rxcode,txcode

                        mov     t1,rxcnt
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        test    rxmask,ina      wc
                        rcr     rxdata,#1
                        djnz    rxbits,#:bit

                        shr     rxdata,#32-9
                        and     rxdata,#$FF
                        test    rxtxmode,#%001  wz
        if_nz           xor     rxdata,#$FF

                        rdlong  t2,par
                        add     t2,rxbuff
                        wrbyte  rxdata,t2
                        sub     t2,rxbuff
                        add     t2,#1
                        and     t2,#$0F
                        wrlong  t2,par

                        jmp     #receive

transmit                jmpret  txcode,rxcode

                        mov     t1,par
                        add     t1,#2 << 2
                        rdlong  t2,t1
                        add     t1,#1 << 2
                        rdlong  t3,t1
                        cmp     t2,t3           wz
        if_z            jmp     #transmit

                        add     t3,txbuff
                        rdbyte  txdata,t3
                        sub     t3,txbuff
                        add     t3,#1
                        and     t3,#$0F
                        wrlong  t3,t1

                        or      txdata,#$100
                        shl     txdata,#2
                        or      txdata,#1
                        mov     txbits,#11
                        mov     txcnt,cnt

:bit                    test    rxtxmode,#%100  wz
                        test    rxtxmode,#%010  wc
        if_z_and_c      xor     txdata,#1
                        shr     txdata,#1       wc
        if_z            muxc    outa,txmask
        if_nz           muxnc   dira,txmask
                        add     txcnt,bitticks

:wait                   jmpret  txcode,rxcode

                        mov     t1,txcnt
                        sub     t1,cnt
                        cmps    t1,#0           wc
        if_nc           jmp     #:wait

                        djnz    txbits,#:bit

                        jmp     #transmit

' Uninitialized cog data
t1                      res     1
t2                      res     1
t3                      res     1

rxtxmode                res     1
bitticks                res     1

rxmask                  res     1
rxbuff                  res     1
rxdata                  res     1
rxbits                  res     1
rxcnt                   res     1
rxcode                  res     1

txmask                  res     1
txbuff                  res     1
txdata                  res     1
txbits                  res     1
txcnt                   res     1
txcode                  res     1

DAT
{{
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
}}
