#define CLOCK 16.0e6
#define DELAY 1

.dseg
mode_1: .byte 2
mode_2: .byte 3

.def actual_mode = r18
.def temp1 = r16
.def temp2 = r17

.cseg
jmp reset
.org OC1Aaddr
    jmp OCI1A_ISR

reset:
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

    ldi temp1, 0
    sts mode_1, temp1
    sts mode_1 + 1, temp1
    sts mode_2, temp1
    sts mode_2 + 1, temp1
    sts mode_2 + 2, temp1  ; Flag = 0

    ldi temp1, (1 << OCIE1A)
    sts TIMSK1, temp1

    .equ PRESCALE = 0b100
    .equ PRESCALE_DIV = 256
    .equ WGM = 0b0100
    .equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))

    ldi temp1, high(TOP)
    sts OCR1AH, temp1
    ldi temp1, low(TOP)
    sts OCR1AL, temp1
    ldi temp1, ((WGM&0b11) << WGM10)
    sts TCCR1A, temp1
    ldi temp1, ((WGM>>2) << WGM12)|(PRESCALE << CS10)
    sts TCCR1B, temp1
    ldi actual_mode, 2
    sei

main:
    rjmp main

OCI1A_ISR:
    push r16
    in r16, SREG
    push r16

    ; verifica se o modo atual eh o cronometro
    cpi actual_mode, 2
    brne continue
    rcall cronometro

    continue:
        ; verifica se o modo atual eh ajustar as horas, se for não atualiza a hora atual
        cpi actual_mode, 3
        breq pass
        rcall hora_atual

    pass:
        pop r16
        out SREG, r16
        pop r16
        reti

hora_atual:
    push temp1
    push temp2

    lds temp2, mode_1 + 1
    inc temp2

    cpi temp2, 60
    breq atualiza_minuto_atual

    sts mode_1 + 1, temp2
    rjmp end

    atualiza_minuto_atual:
        lds temp1, mode_1
        inc temp1
        sts mode_1, temp1

        ldi temp2, 0
        sts mode_1 + 1, temp2

    end:
    pop temp1
    pop temp2
    ret

cronometro:
    push temp1
    push temp2

    ; Verifica se o cronometro esta ativo
    lds temp2, mode_2 + 2
    cpi temp2, 0
    breq pass_soma

    lds temp2, mode_2 + 1
    inc temp2

    ; verifica se chegou em 60 segundos
    cpi temp2, 60
    breq atualiza_minuto_cronometro

    sts mode_2 + 1, temp2

    atualiza_minuto_cronometro:
        lds temp1, mode_2
        inc temp1
        sts mode_2, temp1

        ldi temp2, 0
        sts mode_2 + 1, temp2

    pass_soma:
    pop temp1
    pop temp2
    ret