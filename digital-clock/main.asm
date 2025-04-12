.include "m328pdef.inc" ; Inclui definições do ATmega328P

#define CLOCK 16000000 ;clock speed
#define DELAY 1
#define BAUD 9600       ; Define a taxa de baud da serial
#define UBRR_VALUE (((CLOCK / (BAUD * 16.0)) + 0.5) - 1) ; Calcula UBRR
;#define DELAY_ms 10
;.equ DELAY_CYCLES = int(CLOCK * DELAY_ms) / 1000

.def actual_mode = r18  ; Armazena o modo atual de operação (relógio, cronômetro, ajuste...)
.def temp1 = r16        ; Variavel temporaria
.def temp2 = r17        ; Variavel temporaria
.def tx_byte = r19      ; Byte a ser transmitido pela serial
.def byte_val = r20     ; Byte a ser convertido para ASCII decimal
.def ascii_H = r21      ; Digito ASCII das dezenas
.def ascii_L = r22      ; Digito ASCII das unidades
; Usaremos Z (r31:r30) como ponteiro para strings na memória de programa


.dseg
mode_1: .byte 2
mode_2: .byte 3
adjust_digit_selector: .byte 1 ; Variável para MODO 3 (0=Sec Uni, 1=Sec Dez, 2=Min Uni, 3=Min Dez)


.cseg
; --- Vetores de Interrupção ---
.cseg
.org 0x0000
    jmp reset

.org PCI0addr
    jmp pcint0_isr

.org OC1Aaddr
    jmp OCI1A_ISR

; --- Strings para a Serial ---
str_modo1: .db "[MODO 1] ", 0
str_modo2_run: .db "[MODO 2] RUN ", 0
str_modo2_stop: .db "[MODO 2] STOPPED ", 0
str_modo2_zero: .db "[MODO 2] ZERO", 0
str_modo3_su: .db "[MODO 3] Ajustando a unidade dos segundos", 0
str_modo3_sd: .db "[MODO 3] Ajustando a dezena dos segundos ", 0
str_modo3_mu: .db "[MODO 3] Ajustando a unidade dos minutos ", 0
str_modo3_md: .db "[MODO 3] Ajustando a dezena dos minutos", 0
str_colon: .db ":", 0
str_newline: .db "\r\n ", 0 ; Envia Carriage Return e Line Feed para compatibilidade

reset:
    ; --- Inicialização da Pilha ---
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

	; PB4 como saída
    ldi r16, (1 << PB4)
    out DDRB, r16

    ; Ativa pull-up interno em PB5
    ldi r16, (1 << PB5)
    out PORTB, r16

    ; Habilita interrupção de mudança de pino PCINT0 (PORTB)
    ldi r16, (1 << PCIE0)
    sts PCICR, r16

    ; Habilita interrupção para PB5 (PCINT5)
    ldi r16, (1 << PCINT5)
    sts PCMSK0, r16

	ldi temp1, 0b00011111     ; PB0–PB4 como saída
	out DDRB, temp1

	
    ; --- Inicialização das Variáveis ---
    ldi temp1, 0              ; Carrega o valor 0 no registrador temp1 (r16)
	sts mode_1, temp1         ; Zera os minutos atuais do relógio (mode_1 = 0)
	sts mode_1 + 1, temp1     ; Zera os segundos atuais do relógio (mode_1 + 1 = 0)
	sts mode_2, temp1         ; Zera os minutos do cronômetro (mode_2 = 0)
	sts mode_2 + 1, temp1     ; Zera os segundos do cronômetro (mode_2 + 1 = 0)
	sts mode_2 + 2, temp1     ; Zera a flag de ativação do cronômetro (mode_2 + 2 = 0)
    sts adjust_digit_selector, temp1 ; Zera seletor de ajuste


    ; --- Configuração do Timer1 (Mantido do original) ---
    ldi temp1, (1 << OCIE1A)  ; Carrega no registrador temp1 um valor com o bit OCIE1A ativado (bit que habilita a interrupção do Timer1 Compare Match A)
	sts TIMSK1, temp1         ; Escreve esse valor no registrador TIMSK1, ativando a interrupção do Timer1 (Canal A)
    .equ PRESCALE = 0b100           ; Seleciona o prescaler do Timer1 como 256 (CS12:CS10 = 100)
	.equ PRESCALE_DIV = 256         ; Valor real do prescaler (divisor de clock)
	.equ WGM = 0b0100               ; Define o modo de operação do Timer1 como CTC (Clear Timer on Compare Match)
	.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))

	ldi temp1, high(TOP)              ; Carrega o byte mais significativo do valor TOP no registrador temp1
	sts OCR1AH, temp1                 ; Armazena esse valor no registrador OCR1AH (parte alta do valor de comparação do Timer1)
	ldi temp1, low(TOP)               ; Carrega o byte menos significativo do valor TOP no registrador temp1
	sts OCR1AL, temp1                 ; Armazena esse valor no registrador OCR1AL (parte baixa do valor de comparação do Timer1)
	ldi temp1, ((WGM & 0b11) << WGM10) ; Extrai os 2 bits menos significativos de WGM e posiciona em WGM10/WGM11
	sts TCCR1A, temp1                 ; Configura os bits de modo de operação do Timer1 no registrador TCCR1A
	ldi temp1, ((WGM >> 2) << WGM12) | (PRESCALE << CS10)
	sts TCCR1B, temp1                 ; Configura modo CTC e ativa o prescaler de 256 no registrador TCCR1B
	
    ; --- Configuração do USART ---
    ldi temp1, high(int(UBRR_VALUE))
    sts UBRR0H, temp1
    ldi temp1, low(int(UBRR_VALUE))
    sts UBRR0L, temp1
    ; Habilita transmissor (TXEN0)
    ldi temp1, (1 << TXEN0)
    sts UCSR0B, temp1
    ; Configura formato do frame: 8 bits de dados (UCSZ00, UCSZ01), 1 stop bit (padrão)
    ldi temp1, (1 << UCSZ01) | (1 << UCSZ00)
    sts UCSR0C, temp1

    ; --- Estado Inicial e Interrupções ---
    ldi actual_mode, 1                ; Define o modo inicial como 1 (Relógio)
    sei                               ; Habilita interrupções globais

main:

	
    rcall exibe_digito_0
    rcall delay_multiplex

    rcall exibe_digito_1
    rcall delay_multiplex

    rcall exibe_digito_2
    rcall delay_multiplex

    rcall exibe_digito_3
    rcall delay_multiplex
   


    rjmp main

; --- INTERRUPÇÃO PCINT0 ---
pcint0_isr:
    push r16
    in r16, PINB
    sbrs r16, PB5        ; Se PB5 está em nível alto → botão solto
    rjmp beep

    ; Botão solto → desliga PB4
    cbi PORTB, PB4
    rjmp fim_pcint0_isr

beep:
    ; Botão pressionado → liga PB4
    sbi PORTB, PB4

fim_pcint0_isr:
    pop r16
    reti


; =========================================================================
; ROTINA DE INTERRUPÇÃO DO TIMER 1 - EXECUTADA A CADA SEGUNDO
; =========================================================================
OCI1A_ISR:
    ; --- Salvar Contexto ---
    push temp1          ; r16
    push temp2          ; r17
    push r19            ; tx_byte (usado por USART_Transmit)
    push r20            ; byte_val (usado por Send_Decimal_Byte)
    push r21            ; ascii_H  (usado por Send_Decimal_Byte)
    push r22            ; ascii_L  (usado por Send_Decimal_Byte)
    push r30            ; ZL (usado por USART_Transmit_String)
    push r31            ; ZH (usado por USART_Transmit_String)
    in temp1, SREG      ; Salva SREG
    push temp1

    ; --- Lógica de Atualização (Relógio/Cronômetro) ---
    cpi actual_mode, 1
    breq update_and_send_mode1 ; Se Modo 1, atualiza relógio e envia serial
    cpi actual_mode, 2
    breq update_and_send_mode2 ; Se Modo 2, atualiza cronômetro e envia serial
    cpi actual_mode, 3
    breq send_mode3            ; Se Modo 3, só envia serial (tempo não avança)
    rjmp isr_end               ; Modo inválido? Sai.

update_and_send_mode1:
    rcall hora_atual         ; Atualiza o relógio
    ; Enviar Serial Modo 1: "[MODO 1] MM:SS"
    ldi ZL, low(str_modo1<<1)
    ldi ZH, high(str_modo1<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_1      ; Carrega minutos
    rcall Send_Decimal_Byte   ; Envia MM
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String ; Envia ":"
    lds byte_val, mode_1+1    ; Carrega segundos
    rcall Send_Decimal_Byte   ; Envia SS
    rjmp send_newline_and_exit

update_and_send_mode2:
    rcall cronometro         ; Atualiza o cronômetro (se ativo)
    ; Enviar Serial Modo 2
    lds temp1, mode_2+2      ; Carrega flag de ativação
    cpi temp1, 0
    breq check_mode2_zero    ; Se flag=0 (parado), verifica se está zerado
    ; Se chegou aqui, cronômetro está rodando
    ldi ZL, low(str_modo2_run<<1)
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2      ; Carrega minutos do cronômetro
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String ; Envia ":"
    lds byte_val, mode_2+1    ; Carrega segundos do cronômetro
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

check_mode2_zero:
    lds temp1, mode_2         ; Minutos
    lds temp2, mode_2+1       ; Segundos
    or temp1, temp2           ; Se ambos forem 0, resultado é 0
    brne mode2_stopped        ; Se não for zero, está parado mas não zerado
    ; Se chegou aqui, cronômetro está parado e zerado
    ldi ZL, low(str_modo2_zero<<1)
    ldi ZH, high(str_modo2_zero<<1)
    rcall USART_Transmit_String
    rjmp send_newline_and_exit

mode2_stopped:
    ; Cronômetro parado mas não zerado
    ldi ZL, low(str_modo2_stop<<1)
    ldi ZH, high(str_modo2_stop<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2      ; Carrega minutos do cronômetro
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String ; Envia ":"
    lds byte_val, mode_2+1    ; Carrega segundos do cronômetro
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

send_mode3:
    ; Enviar Serial Modo 3: Mensagem depende do dígito selecionado
    lds temp1, adjust_digit_selector ; Carrega qual dígito está sendo ajustado
    cpi temp1, 0
    breq send_m3_su
    cpi temp1, 1
    breq send_m3_sd
    cpi temp1, 2
    breq send_m3_mu
    cpi temp1, 3
    breq send_m3_md
    rjmp send_newline_and_exit ; Se valor inválido, apenas envia newline

send_m3_su:
    ldi ZL, low(str_modo3_su<<1)
    ldi ZH, high(str_modo3_su<<1)
    rcall USART_Transmit_String
    rjmp send_newline_and_exit
send_m3_sd:
    ldi ZL, low(str_modo3_sd<<1)
    ldi ZH, high(str_modo3_sd<<1)
    rcall USART_Transmit_String
    rjmp send_newline_and_exit
send_m3_mu:
    ldi ZL, low(str_modo3_mu<<1)
    ldi ZH, high(str_modo3_mu<<1)
    rcall USART_Transmit_String
    rjmp send_newline_and_exit
send_m3_md:
    ldi ZL, low(str_modo3_md<<1)
    ldi ZH, high(str_modo3_md<<1)
    rcall USART_Transmit_String
    ;rjmp send_newline_and_exit ; Já vai para o próximo passo

send_newline_and_exit:
    ; Envia Newline para finalizar a mensagem
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String

isr_end:
    ; --- Restaurar Contexto ---
    pop temp1
    out SREG, temp1     ; Restaura SREG
    pop r31             ; ZH
    pop r30             ; ZL
    pop r22             ; ascii_L
    pop r21             ; ascii_H
    pop r20             ; byte_val
    pop r19             ; tx_byte
    pop temp2           ; r17
    pop temp1           ; r16
    reti                ; Retorna da interrupção

; =========================================================================
; FUNÇÕES DE ATUALIZAÇÃO
; =========================================================================
hora_atual:
    push temp1               ; Salva registradores temporários
    push temp2
    lds temp2, mode_1 + 1    ; Carrega segundos atuais do relógio
    inc temp2                ; Incrementa 1 segundo
    cpi temp2, 60            ; Verifica se chegou a 60 segundos
    brne save_seconds        ; Se não, só salva os segundos
atualiza_minuto_atual:
    lds temp1, mode_1        ; Carrega minutos atuais
    inc temp1                ; Incrementa minutos
    cpi temp1, 60            ; Verifica se chegou a 60 minutos (opcional, depende se quer que vire 00:00)
    brne save_minutes
    ldi temp1, 0             ; Zera minutos se chegou a 60
save_minutes:
    sts mode_1, temp1        ; Salva minutos atualizados
    ldi temp2, 0             ; Zera os segundos
save_seconds:
    sts mode_1 + 1, temp2    ; Salva segundos atualizados
    pop temp2                ; Restaura registradores
    pop temp1
    ret                      ; Retorna da função

cronometro:
    push temp1               ; Salva registradores temporários
    push temp2
    lds temp1, mode_2 + 2    ; Lê a flag de ativação do cronômetro
    cpi temp1, 0
    breq crono_end           ; Se for 0, cronômetro está desligado -> sai
    ; Se chegou aqui, cronômetro está ativo
    lds temp2, mode_2 + 1    ; Lê os segundos do cronômetro
    inc temp2                ; Incrementa 1 segundo
    cpi temp2, 60
    brne crono_save_seconds  ; Se não chegou a 60, só salva os segundos
atualiza_minuto_cronometro:
    lds temp1, mode_2        ; Lê os minutos
    inc temp1                ; Incrementa minutos
    cpi temp1, 60            ; Verifica se chegou a 60 minutos (opcional)
    brne crono_save_minutes
    ldi temp1, 0             ; Zera minutos se chegou a 60
crono_save_minutes:
    sts mode_2, temp1        ; Salva minutos atualizados
    ldi temp2, 0             ; Zera os segundos
crono_save_seconds:
    sts mode_2 + 1, temp2    ; Salva os segundos atualizados
crono_end:
    pop temp2                ; Restaura registradores
    pop temp1
    ret                      ; Retorna da função


; =========================================================================
; FUNÇÕES DE DISPLAY
; =========================================================================



exibe_digito_0:
    lds temp1, mode_1 + 1
    ldi temp2, 10
    call dividir
    mov temp1, temp2
    rcall enviar_para_cd4511
    in temp2, PORTB
    sbrc temp2, PB4
        ori temp2, (1 << PB4)
    andi temp2, 0b11110000
    ori temp2, (1 << PB3)
    out PORTB, temp2
    ret

exibe_digito_1:
    lds temp1, mode_1 + 1
    ldi temp2, 10
    call dividir
    rcall enviar_para_cd4511
    in temp2, PORTB
    sbrc temp2, PB4
    ori temp2, (1 << PB4)
    andi temp2, 0b11110000
    ori temp2, (1 << PB2)
    out PORTB, temp2
    ret

exibe_digito_2:
    lds temp1, mode_1
    ldi temp2, 10
    call dividir
    mov temp1, temp2
    rcall enviar_para_cd4511
    in temp2, PORTB
    sbrc temp2, PB4
    ori temp2, (1 << PB4)
    andi temp2, 0b11110000
    ori temp2, (1 << PB1)
    out PORTB, temp2
    ret

exibe_digito_3:
    lds temp1, mode_1
    ldi temp2, 10
    call dividir
    rcall enviar_para_cd4511
    in temp2, PORTB
    sbrc temp2, PB4
    ori temp2, (1 << PB4)
    andi temp2, 0b11110000
    ori temp2, (1 << PB0)
    out PORTB, temp2
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


; =========================================================================
; FUNÇÕES DA SERIAL
; =========================================================================

; --- USART_Transmit ---
; Envia um byte pela serial. Espera o buffer estar livre.
; Entrada: tx_byte (r19) contém o byte a ser enviado
USART_Transmit:
    push temp1          ; Salva r16
tx_wait_loop:
    lds temp1, UCSR0A   ; Lê o status do USART
    sbrs temp1, UDRE0   ; Pula a próxima instrução se o bit UDRE0 (Data Register Empty) estiver setado (1)
    rjmp tx_wait_loop   ; Se não estiver vazio (UDRE0=0), espera
    sts UDR0, tx_byte   ; Coloca o byte no buffer de transmissão (envia)
    pop temp1           ; Restaura r16
    ret

; --- USART_Transmit_String ---
; Envia uma string (terminada em NULL) localizada na memória de programa (Flash).
; Entrada: Z (r31:r30) aponta para o início da string na memória de programa.
; Usa: Z, tx_byte (r19), temp1 (r16)
USART_Transmit_String:
    push temp1          ; Salva r16
    push r30
    push r31
str_loop:
    lpm tx_byte, Z+     ; Carrega byte da memória de programa no tx_byte e incrementa Z
    tst tx_byte         ; Verifica se o byte carregado é zero (NULL terminator)
    breq str_end        ; Se for zero, fim da string
    rcall USART_Transmit ; Envia o byte
    rjmp str_loop       ; Próximo caractere
str_end:
    pop r31
    pop r30
    pop temp1           ; Restaura r16
    ret

; --- Send_Decimal_Byte ---
; Converte um byte (0-99) em dois caracteres ASCII decimais e os envia pela serial.
; Entrada: byte_val (r20) contém o valor (0-99)
; Saída: Envia os dois caracteres ASCII pela serial
; Usa: byte_val (r20), ascii_H (r21), ascii_L (r22), tx_byte (r19), temp1 (r16)
Send_Decimal_Byte:
    push temp1           ; Salva r16
    push r17           ; Salva r17
    push r20           ; Salva byte_val original se precisar depois

    mov temp1, byte_val  ; Copia valor para temp1 (usado por div10)
    rcall div10          ; Chama sub-rotina de divisão por 10
                         ; Resultado: temp1=quociente (dezena), temp2=resto (unidade)

    mov ascii_H, temp1   ; Guarda a dezena
    mov ascii_L, temp2   ; Guarda a unidade

    ; Converte dezena para ASCII ('0' = 0x30)
    subi ascii_H, -0x30  ; Adiciona 0x30
    mov tx_byte, ascii_H ; Prepara para transmitir
    rcall USART_Transmit ; Envia dígito das dezenas

    ; Converte unidade para ASCII
    subi ascii_L, -0x30  ; Adiciona 0x30
    mov tx_byte, ascii_L ; Prepara para transmitir
    rcall USART_Transmit ; Envia dígito das unidades

    pop r20
    pop r17
    pop temp1
    ret


; --- div10 ---
; Sub-rotina simples para dividir por 10 (útil para BCD/ASCII)
; Entrada: temp1 = valor (0-99)
; Saída: temp1 = quociente (Dezena), temp2 = resto (Unidade)
; Usa: temp1, temp2
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