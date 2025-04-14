.include "m328pdef.inc"

#define CLOCK 16000000 ;clock speed
#define DELAY 1
#define BAUD 9600       ; Define a taxa de baud da serial
.equ UBRR_VALUE = 103

.org 0x200
.INCLUDE "modes.asm"
.INCLUDE "display.asm"
.INCLUDE "uart.asm"

; ============================
; Registradores
; ============================
.def zero = r1            ; Registrador sempre zerado para adc
.def actual_mode = r18  ; Armazena o modo atual de opera��o (rel�gio, cron�metro, ajuste...)
.def temp1 = r16        ; Variavel temporaria
.def temp2 = r17        ; Variavel temporaria
.def temp3  = r20       ; Variavel temporaria
.def tx_byte = r19      ; Byte a ser transmitido pela serial
.def byte_val = r21     ; Byte a ser convertido para ASCII decimal
.def ascii_H = r22      ; Digito ASCII das dezenas
.def ascii_L = r23      ; Digito ASCII das unidades

.def botao_pd7 = r24

.dseg
mode_1: .byte 2
mode_2: .byte 3
adjust_digit_selector: .byte 1 ; Vari�vel para MODO 3 (0=Sec Uni, 1=Sec Dez, 2=Min Uni, 3=Min Dez)
trocar_modo_flag: .byte 1
blink_counter: .byte 1       ; Novo contador para controle da piscagem

.cseg
; ============================
; Vetores de Interrup��o
; ============================
.org 0x0000
    jmp reset

.org PCI0addr
    jmp pcint0_isr     ; Interrup��o do PB5 (PORTB)

.org PCI2addr
    jmp pcint2_isr     ; Interrup��o do PD6 e PD7 (PORTD)

.org OC1Aaddr
    jmp OCI1A_ISR      ; Interrup��o TIMER

.org UDREaddr
    jmp uart_udre_isr


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

; ============================
; Reset
; ============================
reset:
	; --- Inicializa��o das Vari�veis ---
    ldi temp1, 0              ; Carrega o valor 0 no registrador temp1 (r16)
	sts mode_1, temp1         ; Zera os minutos atuais do rel�gio (mode_1 = 0)
	sts mode_1 + 1, temp1     ; Zera os segundos atuais do rel�gio (mode_1 + 1 = 0)
	sts mode_2, temp1         ; Zera os minutos do cron�metro (mode_2 = 0)
	sts mode_2 + 1, temp1     ; Zera os segundos do cron�metro (mode_2 + 1 = 0)
	sts mode_2 + 2, temp1     ; Zera a flag de ativa��o do cron�metro (mode_2 + 2 = 0)
    sts adjust_digit_selector, temp1 ; Zera seletor de ajuste

	ldi temp1, 0b00011111     ; PB0�PB4 como sa�da
	out DDRB, temp1

    ; ========== Configura PD6 e PD7 ==========
    in temp1, DDRD
    andi temp1, ~(1 << PD6 | 1 << PD7)
    out DDRD, temp1

    in temp1, PORTD
    ori temp1, (1 << PD6 | 1 << PD7)
    out PORTD, temp1

    ; ========== Configura PB5 ==========
    in temp1, DDRB
    andi temp1, ~(1 << PB5)
    out DDRB, temp1

    in temp1, PORTB
    ori temp1, (1 << PB5)
    out PORTB, temp1

    ; Habilita interrup��o em PCINT22 (PD6) e PCINT23 (PD7)
    ldi temp1, (1 << PCINT22) | (1 << PCINT23)
    sts PCMSK2, temp1

    ; Habilita interrup��o em PCINT5 (PB5)
    ldi temp1, (1 << PCINT5)
    sts PCMSK0, temp1

    ; Ativa grupos PCINT2 (PORTD) e PCINT0 (PORTB)
    ldi temp1, (1 << PCIE2) | (1 << PCIE0)
    sts PCICR, temp1

	 ; --- Configura��o do Timer1 (Mantido do original) ---
    ldi temp1, (1 << OCIE1A)  ; Carrega no registrador temp1 um valor com o bit OCIE1A ativado (bit que habilita a interrup��o do Timer1 Compare Match A)
	sts TIMSK1, temp1         ; Escreve esse valor no registrador TIMSK1, ativando a interrup��o do Timer1 (Canal A)
    .equ PRESCALE = 0b100           ; Seleciona o prescaler do Timer1 como 256 (CS12:CS10 = 100)
	.equ PRESCALE_DIV = 256         ; Valor real do prescaler (divisor de clock)
	.equ WGM = 0b0100               ; Define o modo de opera��o do Timer1 como CTC (Clear Timer on Compare Match)
	.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))

	ldi temp1, high(TOP)              ; Carrega o byte mais significativo do valor TOP no registrador temp1
	sts OCR1AH, temp1                 ; Armazena esse valor no registrador OCR1AH (parte alta do valor de compara��o do Timer1)
	ldi temp1, low(TOP)               ; Carrega o byte menos significativo do valor TOP no registrador temp1
	sts OCR1AL, temp1                 ; Armazena esse valor no registrador OCR1AL (parte baixa do valor de compara��o do Timer1)
	ldi temp1, ((WGM & 0b11) << WGM10) ; Extrai os 2 bits menos significativos de WGM e posiciona em WGM10/WGM11
	sts TCCR1A, temp1                 ; Configura os bits de modo de opera��o do Timer1 no registrador TCCR1A
	ldi temp1, ((WGM >> 2) << WGM12) | (PRESCALE << CS10)
	sts TCCR1B, temp1                 ; Configura modo CTC e ativa o prescaler de 256 no registrador TCCR1B

	ldi temp1, high(UBRR_VALUE)
	sts UBRR0H, temp1
	ldi temp1, low(UBRR_VALUE)
	sts UBRR0L, temp1
	ldi temp1, (1 << TXEN0) | (1 << UDRIE0)  ; TX habilitado + interrup��o
	sts UCSR0B, temp1
	ldi temp1, (1 << UCSZ01) | (1 << UCSZ00)
	sts UCSR0C, temp1

    ; --- Estado Inicial e Interrup��es ---
    ldi actual_mode, 1                ; Define o modo inicial como 1 (Rel�gio)
    sei                               ; Habilita interrup��es globais

main_loop:
	rcall multiplexar_display
    rjmp main_loop

; ============================
; ISR: PCINT2 (PD6 e PD7)
; ============================
pcint2_isr:
    push temp1
    push temp2
    push temp3
    in temp1, SREG
    push temp1
		
    in temp2, PIND
    sbrc temp2, PD6
    rjmp verifica_pd7
    ldi temp3, 5

; PD6 (borda de descida)
verifica_pd6:
    in temp1, PIND
    sbrc temp1, PD6
    rjmp verifica_pd7
    dec temp3
    brne verifica_pd6

	;; A��O PD6 | reset
	cpi actual_mode, 2
	brne checa_reset_modo3
	rcall handle_reset_modo2
	rjmp fim_acao_pd6

	checa_reset_modo3:
	cpi actual_mode, 3
	brne fim_acao_pd6
	rcall handle_reset_modo3

	fim_acao_pd6:

; PD7 (borda de descida)
verifica_pd7:
    in temp2, PIND
    sbrc temp2, PD7
    rjmp end_pcint2_isr
    ldi temp3, 5

verifica_pd7_loop:
    in temp1, PIND
    sbrc temp1, PD7
    rjmp end_pcint2_isr
    dec temp3
    brne verifica_pd7_loop

	;; A��O PD7 | start

	cpi actual_mode, 2
	brne pass_start_modo2
	rcall beep_modo
	rcall handle_start_modo2
	rjmp pass_start_modo3

	pass_start_modo2:
	cpi actual_mode, 3
	brne pass_start_modo3
	rcall handle_start_modo3

	pass_start_modo3:

end_pcint2_isr:
    pop temp1
    out SREG, temp1

    pop temp3
    pop temp2
    pop temp1
    reti

; ============================
; ISR: PCINT0 (PB5)
; ============================
pcint0_isr:
    push temp1
    push temp2
    push temp3
    in temp1, SREG
    push temp1

    in temp2, PINB
    sbrc temp2, PB5
    rjmp end_isr
    ldi temp3, 5
verifica_pb5:
    in temp1, PINB
    sbrc temp1, PB5
    rjmp end_isr
    dec temp3
    brne verifica_pb5

    ;; ---------- A��O
	rcall beep_modo
    inc actual_mode
    cpi actual_mode, 4
    brne end_isr
    ldi actual_mode, 1
    ;; ----------

end_isr:
    pop temp1
    out SREG, temp1

    pop temp3
    pop temp2
    pop temp1
    reti

; =========================================================================
; ROTINA DE INTERRUP��O DO TIMER 1 - EXECUTADA A CADA SEGUNDO
; =========================================================================
OCI1A_ISR:
    ; --- Salvar Contexto ---
    push temp1              
    push temp2              
    push temp3              
    in temp1, SREG          
    push temp1

    ; --- L�gica de Atualiza��o ---
    cpi actual_mode, 3     
    breq passa_hora

    rcall hora_atual

	passa_hora:

	lds temp1, mode_2 + 2
	cpi temp1, 1
	brne pass_cronometro
    rcall cronometro
	pass_cronometro:

    ; --- UART
    cpi actual_mode, 1
	brne pass_uart_mode1
    rcall send_mode1

	pass_uart_mode1:

    cpi actual_mode, 2
	brne pass_uart_mode2
    rcall send_mode2

	pass_uart_mode2:
    cpi actual_mode, 3
    brne continuar_uart
    rcall send_mode3

continuar_uart:
isr_end:
    ; --- Restaurar Contexto ---
    pop temp1
    out SREG, temp1
    pop temp3
    pop temp2
    pop temp1
    reti

beep_modo:
    sbi PORTB, PB4
    rcall delay_multiplex
    cbi PORTB, PB4
    ret