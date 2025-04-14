; =========================================================================
; FUNÇÕES DE DISPLAY
; =========================================================================
multiplexar_display:
    ; Seleciona os dados corretos conforme o modo
    cpi actual_mode, 2
    breq usa_dados_cronometro
	cpi actual_mode, 3
	brne usa_dados_relogio
	rjmp multiplexar_display_modo3

usa_dados_relogio:
    lds temp1, mode_1 + 1    ; Segundos
    ldi temp2, 10
    call dividir             ; temp1 = dezena, temp2 = unidade
    mov r23, temp2           ; Sec Unid
    mov r24, temp1           ; Sec Dez

    lds temp1, mode_1        ; Minutos
    ldi temp2, 10
    call dividir
    mov r25, temp2           ; Min Unid
    mov r26, temp1           ; Min Dez
    rjmp exibir_valores

usa_dados_cronometro:
    lds temp1, mode_2 + 1
    ldi temp2, 10
    call dividir
    mov r23, temp2
    mov r24, temp1

    lds temp1, mode_2
    ldi temp2, 10
    call dividir
    mov r25, temp2
    mov r26, temp1

exibir_valores:
    mov temp1, r23
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB3)
    out PORTB, temp2
    rcall delay_multiplex

    mov temp1, r24
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB2)
    out PORTB, temp2
    rcall delay_multiplex

    mov temp1, r25
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB1)
    out PORTB, temp2
    rcall delay_multiplex

    mov temp1, r26
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB0)
    out PORTB, temp2
    rcall delay_multiplex

    ret


enviar_para_cd4511:
    lsl temp1
    lsl temp1
    in temp2, PORTD
    andi temp2, 0b11000011
    or temp2, temp1
    out PORTD, temp2
    ret

dividir:
    push r19
    clr r19
div_loop:
    cp temp1, temp2
    brlo fim_div
    sub temp1, temp2
    inc r19
    rjmp div_loop
fim_div:
    mov temp2, temp1
    mov temp1, r19
    pop r19
    ret

delay_multiplex:
    push r24
    push r25
    ldi r25, high(5000) ;SUJEITO A MUDANÇA
    ldi r24, low(5000)
delay_loop:
    sbiw r24, 1
    brne delay_loop
    pop r25
    pop r24
    ret

;-------------------------

multiplexar_display_modo3:
    ; Carrega valores atuais do relógio
    lds temp1, mode_1 + 1    ; Carrega os segundos do relógio
    ldi temp2, 10
    call dividir             ; Divide em dezena e unidade
    mov r23, temp2           ; Unidade dos segundos em r23
    mov r24, temp1           ; Dezena dos segundos em r24

    lds temp1, mode_1        ; Carrega os minutos do relógio
    ldi temp2, 10
    call dividir             ; Divide em dezena e unidade
    mov r25, temp2           ; Unidade dos minutos em r25
    mov r26, temp1           ; Dezena dos minutos em r26

    ; Incrementar o contador de piscagem
    lds temp1, blink_counter
    inc temp1
    cpi temp1, 150            ; Ajuste esse valor para alterar a velocidade da piscagem
                             ; Valores maiores = pisca mais devagar
    brlo salvar_contador
    ldi temp1, 0             ; Reseta o contador quando atinge o limite
salvar_contador:
    sts blink_counter, temp1

    ; Verificar se deve piscar baseado no contador
    cpi temp1, 10            ; Metade do tempo ligado, metade desligado
    brlo exibe_normal        ; Se contador < 10, exibe o dígito normalmente
    
    ; Se contador >= 10, apaga o dígito selecionado
    lds temp1, adjust_digit_selector
    cpi temp1, 0
    brne testa_sd
    ldi r23, 10              ; Apaga apenas unidade dos segundos
    rjmp exibe_normal
testa_sd:
    cpi temp1, 1
    brne testa_mu
    ldi r24, 10              ; Apaga apenas dezena dos segundos
    rjmp exibe_normal
testa_mu:
    cpi temp1, 2
    brne testa_md
    ldi r25, 10              ; Apaga apenas unidade dos minutos
    rjmp exibe_normal
testa_md:
    cpi temp1, 3
    brne exibe_normal
    ldi r26, 10              ; Apaga apenas dezena dos minutos

exibe_normal:
    ; Configura o Timer0 para próxima alternância
    ldi temp1, (1 << CS02) | (0 << CS01) | (1 << CS00)  ; Prescaler = 1024
    out TCCR0B, temp1

    ; Exibe cada dígito
	mov temp1, r23           ; Unidade dos segundos
    cpi temp1, 10            ; Verifica se é para apagar (valor 10)
    breq desliga_display_su
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB3)
    out PORTB, temp2
    rjmp continua_sd

desliga_display_su:
    in temp2, PORTB
    andi temp2, 0b11110111   ; Desliga o bit PB3 (apaga o display)
    out PORTB, temp2

continua_sd:
    rcall delay_multiplex

    mov temp1, r24           ; Dezena dos segundos
    cpi temp1, 10
    breq desliga_display_sd
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB2)
    out PORTB, temp2
    rjmp continua_mu

desliga_display_sd:
    in temp2, PORTB
    andi temp2, 0b11111011   ; Desliga o bit PB2
    out PORTB, temp2

continua_mu:
    rcall delay_multiplex

    mov temp1, r25           ; Unidade dos minutos
    cpi temp1, 10
    breq desliga_display_mu
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB1)
    out PORTB, temp2
    rjmp continua_md

desliga_display_mu:
    in temp2, PORTB
    andi temp2, 0b11111101   ; Desliga o bit PB1
    out PORTB, temp2

continua_md:
    rcall delay_multiplex

    mov temp1, r26           ; Dezena dos minutos
    cpi temp1, 10
    breq desliga_display_md
    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB0)
    out PORTB, temp2
    rjmp fim_multiplex_modo3

desliga_display_md:
    in temp2, PORTB
    andi temp2, 0b11111110   ; Desliga o bit PB0
    out PORTB, temp2

fim_multiplex_modo3:
    rcall delay_multiplex
    ret