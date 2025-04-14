; UART com Transmissão por Interrupção no ATmega328P

; ============================
; DSEG - Variáveis de Controle
; ============================
.dseg
uart_buffer:     .byte 64      ; Buffer de transmissão
uart_head:       .byte 1       ; Ponteiro de escrita
uart_tail:       .byte 1       ; Ponteiro de leitura
uart_sending:    .byte 1       ; Flag de envio em andamento

.cseg
; ============================
; CONFIGURAÇÃO USART (no RESET)
; ============================
; --- Dentro do reset ---
ldi temp1, high(UBRR_VALUE)
sts UBRR0H, temp1
ldi temp1, low(UBRR_VALUE)
sts UBRR0L, temp1
ldi temp1, (1 << TXEN0) | (1 << UDRIE0)  ; TX habilitado + interrupção
sts UCSR0B, temp1
ldi temp1, (1 << UCSZ01) | (1 << UCSZ00)
sts UCSR0C, temp1


; ============================
; UART_Enqueue_Byte
; Entrada: r19 = byte a ser enviado
; ============================
UART_Enqueue_Byte:
    push temp1
    push temp2
    push r30
    push r31

    lds temp1, uart_head
    ldi temp2, 64
    inc temp1
    cp temp1, temp2
    brlo no_wrap_uart
    ldi temp1, 0
no_wrap_uart:
    sts uart_head, temp1

    ; escreve no buffer usando ponteiro Z
    ldi ZH, high(uart_buffer)
    ldi ZL, low(uart_buffer)
    add ZL, temp1
    adc ZH, zero
    st Z, r19

    ; Inicia envio se não estiver enviando
    lds temp2, uart_sending
    cpi temp2, 0
    brne uart_enqueue_exit

    ldi temp2, 1
    sts uart_sending, temp2
    ldi temp2, (1 << TXEN0) | (1 << UDRIE0)
    sts UCSR0B, temp2

uart_enqueue_exit:
    pop r31
    pop r30
    pop temp2
    pop temp1
    ret



; ============================
; USART_Transmit_String_Async
; Entrada: Z aponta para string na Flash
; ============================
USART_Transmit_String_Async:
    push r30
    push r31
str_async_loop:
    lpm r19, Z+
    tst r19
    breq str_async_end
    rcall UART_Enqueue_Byte
    rjmp str_async_loop
str_async_end:
    pop r31
    pop r30
    ret


; ============================
; Interrupção USART - UDRE0
; ============================

uart_udre_isr:
    push temp1
    push temp2
    push r19
    push r21
    push r22
    push r23

    lds temp1, uart_tail
    lds temp2, uart_head
    cp temp1, temp2
    breq uart_buffer_empty

    ; Avança leitura
    ldi temp2, 64
    inc temp1
    cp temp1, temp2
    brlo no_wrap_read
    ldi temp1, 0
no_wrap_read:
    sts uart_tail, temp1

    ldi ZH, high(uart_buffer)
	ldi ZL, low(uart_buffer)
	add ZL, temp1
	adc ZH, zero
	ld r19, Z

    sts UDR0, r19
    rjmp uart_isr_exit

uart_buffer_empty:
    ldi temp1, (1 << TXEN0)        ; Desativa interrupção, mantém TX
    sts UCSR0B, temp1
    ldi temp1, 0
    sts uart_sending, temp1

uart_isr_exit:
    pop r23
    pop r22
    pop r21
    pop r19
    pop temp2
    pop temp1
    reti


; ============================
; Send_Decimal_Byte_Async
; Entrada: byte_val (r20)
; ============================
Send_Decimal_Byte_Async:
    push temp1
    push r17
    push r20

    mov temp1, byte_val
    rcall div10

    mov ascii_H, temp1
    mov ascii_L, temp2

    subi ascii_H, -0x30
    mov r19, ascii_H
    rcall UART_Enqueue_Byte

    subi ascii_L, -0x30
    mov r19, ascii_L
    rcall UART_Enqueue_Byte

    pop r20
    pop r17
    pop temp1
    ret


; ============================
; send_mode1 com UART assíncrona
; ============================
send_mode1:
    ldi ZL, low(str_modo1<<1)
    ldi ZH, high(str_modo1<<1)
    rcall USART_Transmit_String_Async

    lds byte_val, mode_1
    rcall Send_Decimal_Byte_Async

    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async

    lds byte_val, mode_1+1
    rcall Send_Decimal_Byte_Async

    rjmp send_newline_and_exit

send_mode2:
    lds temp1, mode_2+2
    cpi temp1, 0
    breq check_mode2_zero
    ldi ZL, low(str_modo2_run<<1)
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String_Async
    lds byte_val, mode_2
    rcall Send_Decimal_Byte_Async
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async
    lds byte_val, mode_2+1
    rcall Send_Decimal_Byte_Async
    rjmp send_newline_and_exit

check_mode2_zero:
    lds temp1, mode_2
    lds temp2, mode_2+1
    or temp1, temp2
    brne mode2_stopped
    ldi ZL, low(str_modo2_zero<<1)
    ldi ZH, high(str_modo2_zero<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit

mode2_stopped:
    ldi ZL, low(str_modo2_stop<<1)
    ldi ZH, high(str_modo2_stop<<1)
    rcall USART_Transmit_String_Async
    lds byte_val, mode_2
    rcall Send_Decimal_Byte_Async
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async
    lds byte_val, mode_2+1
    rcall Send_Decimal_Byte_Async
    rjmp send_newline_and_exit

send_mode3:
    lds temp1, adjust_digit_selector
    cpi temp1, 0
    breq send_m3_su
    cpi temp1, 1
    breq send_m3_sd
    cpi temp1, 2
    breq send_m3_mu
    cpi temp1, 3
    breq send_m3_md
    rjmp send_newline_and_exit

send_m3_su:
    ldi ZL, low(str_modo3_su<<1)
    ldi ZH, high(str_modo3_su<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit
send_m3_sd:
    ldi ZL, low(str_modo3_sd<<1)
    ldi ZH, high(str_modo3_sd<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit
send_m3_mu:
    ldi ZL, low(str_modo3_mu<<1)
    ldi ZH, high(str_modo3_mu<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit
send_m3_md:
    ldi ZL, low(str_modo3_md<<1)
    ldi ZH, high(str_modo3_md<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit

send_newline_and_exit:
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String_Async
    ret

div10:
    clr temp2           ; temp2 será o quociente (dezenas)
div10_loop:
    cpi temp1, 10       ; Compara com 10
    brlo div10_end      ; Se for menor, acabou
    subi temp1, 10      ; Subtrai 10
    inc temp2           ; Incrementa quociente
    rjmp div10_loop
div10_end:
    ; No fim: temp1 tem o resto (unidade), temp2 tem o quociente (dezena)
    ; Troca para retornar como especificado (temp1=quociente, temp2=resto)
    push temp1
    mov temp1, temp2
    pop temp2
    ret
