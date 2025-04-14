; UART com Transmiss�o por Interrup��o no ATmega328P

; ============================
; DSEG - Vari�veis de Controle
; ============================
.dseg
uart_buffer:     .byte 64      ; Buffer de transmiss�o
uart_head:       .byte 1       ; Ponteiro de escrita
uart_tail:       .byte 1       ; Ponteiro de leitura
uart_sending:    .byte 1       ; Flag de envio em andamento

.cseg
; ============================
; CONFIGURA��O USART (no RESET)
; ============================
; --- Dentro do reset ---
ldi temp1, high(UBRR_VALUE)
sts UBRR0H, temp1
ldi temp1, low(UBRR_VALUE)
sts UBRR0L, temp1
ldi temp1, (1 << TXEN0) | (1 << UDRIE0)  ; TX habilitado + interrup��o
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

    ; Inicia envio se n�o estiver enviando
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
; Envia uma string armazenada na memória Flash, byte a byte de forma assíncrona
; ============================
USART_Transmit_String_Async:
    push r30                     ; Salva parte baixa do ponteiro Z (r30)
    push r31                     ; Salva parte alta do ponteiro Z (r31)

str_async_loop:
    lpm r19, Z+                  ; Lê byte da memória Flash apontada por Z e incrementa Z
    tst r19                      ; Testa se o byte é zero (fim da string)
    breq str_async_end           ; Se for zero, termina a rotina
    rcall UART_Enqueue_Byte      ; Enfileira o byte para envio assíncrono
    rjmp str_async_loop          ; Repete para o próximo caractere

str_async_end:
    pop r31                      ; Restaura parte alta de Z
    pop r30                      ; Restaura parte baixa de Z
    ret                          ; Retorna da sub-rotina


; ============================
; Interrupção USART - UDRE0
; Ativada quando o registrador de dados está vazio (pronto para novo byte)
; ============================
uart_udre_isr:
    push temp1                   ; Salva registradores usados na interrupção
    push temp2
    push r19
    push r21
    push r22
    push r23

    lds temp1, uart_tail         ; Lê a posição atual de leitura (tail)
    lds temp2, uart_head         ; Lê a posição de escrita (head)
    cp temp1, temp2              ; Compara se o buffer está vazio
    breq uart_buffer_empty       ; Se iguais, nada para enviar

    ; ============================
    ; Atualiza posição de leitura do buffer circular
    ; ============================
    ldi temp2, 64                ; Tamanho total do buffer circular
    inc temp1                    ; Avança para o próximo byte
    cp temp1, temp2              ; Verifica se chegou ao final
    brlo no_wrap_read            ; Se não chegou, continua
    ldi temp1, 0                 ; Se passou, volta para o início

no_wrap_read:
    sts uart_tail, temp1         ; Atualiza a posição do tail

    ; ============================
    ; Lê o byte do buffer circular e envia pela UART
    ; ============================
    ldi ZH, high(uart_buffer)    ; Carrega parte alta do ponteiro para o buffer
    ldi ZL, low(uart_buffer)     ; Carrega parte baixa do ponteiro
    add ZL, temp1                ; Soma o offset (tail)
    adc ZH, zero                 ; Adiciona carry se houver overflow
    ld r19, Z                    ; Lê o byte da posição calculada

    sts UDR0, r19                ; Envia o byte para o registrador de transmissão
    rjmp uart_isr_exit           ; Sai da interrupção

uart_buffer_empty:
    ; ============================
    ; Se o buffer estiver vazio, desativa a interrupção UDRE0
    ; ============================
    ldi temp1, (1 << TXEN0)      ; Mantém apenas o transmissor ativado
    sts UCSR0B, temp1            ; Atualiza controle da UART
    ldi temp1, 0
    sts uart_sending, temp1      ; Marca que transmissão terminou

uart_isr_exit:
    pop r23                      ; Restaura registradores
    pop r22
    pop r21
    pop r19
    pop temp2
    pop temp1
    reti                         ; Retorna da interrupção


; ============================
; Send_Decimal_Byte_Async
; Entrada: byte_val (r20)
; Converte um byte (0–99) em ASCII e envia assíncronamente
; ============================
Send_Decimal_Byte_Async:
    push temp1                   ; Salva temporário
    push r17                     ; Reservado para possíveis cálculos
    push r20                     ; Salva byte original

    mov temp1, byte_val          ; Copia o valor para temp1
    rcall div10                  ; Divide por 10: temp1 = dezena, temp2 = unidade

    mov ascii_H, temp1           ; Armazena dezena
    mov ascii_L, temp2           ; Armazena unidade

    subi ascii_H, -0x30          ; Converte para ASCII
    mov r19, ascii_H
    rcall UART_Enqueue_Byte

    subi ascii_L, -0x30          ; Converte para ASCII
    mov r19, ascii_L
    rcall UART_Enqueue_Byte

    pop r20                      ; Restaura registradores
    pop r17
    pop temp1
    ret


; ============================
; send_mode1 com UART assíncrona
; Envia [MODO 1] MM:SS formatado
; ============================
send_mode1:
    ; ================================
    ; Envia o texto “[MODO 1]” pela UART (modo relógio)
    ; ================================
    ldi ZL, low(str_modo1<<1)         ; Carrega parte baixa do endereço da string "[MODO 1]"
    ldi ZH, high(str_modo1<<1)        ; Carrega parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a string de forma assíncrona

    ; ================================
    ; Envia os minutos (MM)
    ; ================================
    lds byte_val, mode_1              ; Carrega os minutos do relógio
    rcall Send_Decimal_Byte_Async     ; Envia os minutos como dois dígitos ASCII

    ; ================================
    ; Envia o caractere “:”
    ; ================================
    ldi ZL, low(str_colon<<1)         ; Carrega endereço da string ":"
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async ; Envia ":" pela UART

    ; ================================
    ; Envia os segundos (SS)
    ; ================================
    lds byte_val, mode_1+1            ; Carrega os segundos do relógio
    rcall Send_Decimal_Byte_Async     ; Envia os segundos como dois dígitos ASCII

    ; ================================
    ; Finaliza com quebra de linha
    ; ================================
    rjmp send_newline_and_exit        ; Envia \r\n e retorna


; ================================
; send_mode2 com UART assíncrona
; Envia o estado do cronômetro:
; "[MODO 2] RUN MM:SS", "[MODO 2] STOPPED MM:SS" ou "[MODO 2] ZERO"
; ================================
send_mode2:
    lds temp1, mode_2+2               ; Carrega a flag de ativação do cronômetro
    cpi temp1, 0                      ; Verifica se a flag está desativada (0)
    breq check_mode2_zero            ; Se estiver desativado, verifica se está zerado ou parado

    ; ================================
    ; Cronômetro está rodando → envia "[MODO 2] RUN MM:SS"
    ; ================================
    ldi ZL, low(str_modo2_run<<1)    ; Carrega parte baixa do endereço da string "[MODO 2] RUN"
    ldi ZH, high(str_modo2_run<<1)   ; Carrega parte alta
    rcall USART_Transmit_String_Async ; Envia string de forma assíncrona

    lds byte_val, mode_2             ; Carrega os minutos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia minutos formatados como dois dígitos ASCII

    ldi ZL, low(str_colon<<1)        ; Carrega endereço do caractere ":"
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async ; Envia ":" pela UART

    lds byte_val, mode_2+1           ; Carrega os segundos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia segundos formatados como dois dígitos ASCII

    rjmp send_newline_and_exit       ; Finaliza com \r\n e retorna


check_mode2_zero:
    lds temp1, mode_2              ; Carrega os minutos do cronômetro
    lds temp2, mode_2+1            ; Carrega os segundos do cronômetro
    or temp1, temp2                ; Verifica se ambos são zero (resultado = 0 só se os dois forem zero)
    brne mode2_stopped             ; Se qualquer valor for diferente de zero, pula para "mode2_stopped"

    ; ================================
    ; Cronômetro está parado e zerado → envia "[MODO 2] ZERO"
    ; ================================
    ldi ZL, low(str_modo2_zero<<1) ; Carrega parte baixa do endereço da string "[MODO 2] ZERO"
    ldi ZH, high(str_modo2_zero<<1); Carrega parte alta
    rcall USART_Transmit_String_Async ; Envia a string "[MODO 2] ZERO" pela UART

    rjmp send_newline_and_exit     ; Finaliza com quebra de linha e retorna


mode2_stopped:
    ; ================================
    ; Cronômetro parado (não zerado) → envia "[MODO 2] STOPPED MM:SS"
    ; ================================
    ldi ZL, low(str_modo2_stop<<1)   ; Carrega parte baixa do endereço da string "[MODO 2] STOPPED"
    ldi ZH, high(str_modo2_stop<<1)  ; Carrega parte alta
    rcall USART_Transmit_String_Async ; Envia a string "[MODO 2] STOPPED" pela UART

    lds byte_val, mode_2             ; Carrega os minutos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os minutos como dois dígitos ASCII

    ldi ZL, low(str_colon<<1)        ; Carrega endereço da string ":"
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async ; Envia o caractere ":" pela UART

    lds byte_val, mode_2+1           ; Carrega os segundos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os segundos como dois dígitos ASCII

    rjmp send_newline_and_exit       ; Finaliza com \r\n e retorna


; ============================
; send_mode3 com UART assíncrona
; Envia uma mensagem indicando qual dígito está sendo ajustado no modo 3
; ============================
send_mode3:
    lds temp1, adjust_digit_selector ; Lê o valor do seletor de dígitos (0 a 3)
    cpi temp1, 0                     ; Verifica se está ajustando unidade dos segundos
    breq send_m3_su                  ; Se sim, envia string correspondente
    cpi temp1, 1                     ; Verifica se está ajustando dezena dos segundos
    breq send_m3_sd
    cpi temp1, 2                     ; Verifica se está ajustando unidade dos minutos
    breq send_m3_mu
    cpi temp1, 3                     ; Verifica se está ajustando dezena dos minutos
    breq send_m3_md
    rjmp send_newline_and_exit      ; Se valor inválido, apenas envia nova linha

send_m3_su:
    ; ============================
    ; Envia string: "[MODO 3] Ajustando a unidade dos segundos"
    ; ============================
    ldi ZL, low(str_modo3_su<<1)     ; Carrega parte baixa do endereço da string
    ldi ZH, high(str_modo3_su<<1)    ; Carrega parte alta do endereço da string
    rcall USART_Transmit_String_Async ; Envia a string pela UART
    rjmp send_newline_and_exit       ; Finaliza com nova linha

send_m3_sd:
    ; ============================
    ; Envia string: "[MODO 3] Ajustando a dezena dos segundos"
    ; ============================
    ldi ZL, low(str_modo3_sd<<1)
    ldi ZH, high(str_modo3_sd<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit

send_m3_mu:
    ; ============================
    ; Envia string: "[MODO 3] Ajustando a unidade dos minutos"
    ; ============================
    ldi ZL, low(str_modo3_mu<<1)
    ldi ZH, high(str_modo3_mu<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit

send_m3_md:
    ; ============================
    ; Envia string: "[MODO 3] Ajustando a dezena dos minutos"
    ; ============================
    ldi ZL, low(str_modo3_md<<1)
    ldi ZH, high(str_modo3_md<<1)
    rcall USART_Transmit_String_Async
    rjmp send_newline_and_exit


; ============================
; Envia caractere de nova linha e retorna
; (quebra de linha para formatar saída UART)
; ============================
send_newline_and_exit:
    ldi ZL, low(str_newline<<1)     ; Endereço da string "\r\n"
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String_Async
    ret


; ============================
; div10
; Divide valor de temp1 por 10
; Retorno: temp1 = dezena (quociente), temp2 = unidade (resto)
; ============================
div10:
    clr temp2                       ; Zera temp2 (será o quociente)
div10_loop:
    cpi temp1, 10                   ; Verifica se temp1 ainda é maior ou igual a 10
    brlo div10_end                  ; Se for menor que 10, fim da divisão
    subi temp1, 10                  ; Subtrai 10 de temp1
    inc temp2                       ; Incrementa o quociente
    rjmp div10_loop                 ; Repete até temp1 < 10

div10_end:
    push temp1                      ; Salva o resto (que ainda está em temp1)
    mov temp1, temp2                ; Coloca o quociente (dezena) em temp1
    pop temp2                       ; Recupera o resto (unidade) para temp2
    ret                             ; Retorna com temp1 = dezena, temp2 = unidade