; GEOMTEST.ASM
; Version 4 - silent 128x64 geometry test.
;
; No prompt is displayed while waiting for input.  The screen contains only
; the geometry markers, and the cursor is parked safely near the center.
;
; Expected in 1024x768 / 128x64 mode:
;   R = row 1,  column 128 (extreme top-right)
;   L = row 63, column 1
;   Q = row 63, column 128
;   B = row 64, column 1   (extreme bottom-left)
;   Z = row 64, column 127 (one cell left of extreme bottom-right)
;
; Press any key while the test is displayed to return to CP/M.

        ORG     0100H
BDOS    EQU     0005H

START:  LXI     H,SEQ
        CALL    PUTS

WAITKEY:
        MVI     E,0FFH
        MVI     C,6
        CALL    BDOS
        ORA     A
        JZ      WAITKEY

        LXI     H,EXITSEQ
        CALL    PUTS
        RET

PUTS:   MOV     A,M
        ORA     A
        RZ
        MOV     E,A
        MVI     C,6
        PUSH    H
        CALL    BDOS
        POP     H
        INX     H
        JMP     PUTS

SEQ:
        DB      1BH,'[2J'
        DB      1BH,'[H'
        DB      1BH,'[1;128H','R'
        DB      1BH,'[63;1H','L'
        DB      1BH,'[63;128H','Q'
        DB      1BH,'[64;1H','B'
        DB      1BH,'[64;127H','Z'
        DB      1BH,'[32;64H'
        DB      0

EXITSEQ:
        DB      1BH,'[H'
        DB      0

        END     START
