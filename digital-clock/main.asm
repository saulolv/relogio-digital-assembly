#define CLOCK 16000000 ;clock speed
#define DELAY 1
;#define DELAY_ms 10
;.equ DELAY_CYCLES = int(CLOCK * DELAY_ms) / 1000

.dseg					;Sram
mode_1: .byte 2			;Guarda o tempo atual (minuto, segundo).
mode_2: .byte 3			;Guarda o cronômetro (minuto, segundo, flag de ativação).

.def actual_mode = r18	;Armazena o modo atual de operação (relógio, cronômetro, ajuste...)
.def temp1 = r16		;Variavel temporaria
.def temp2 = r17		;Variavel temporaria

.cseg
.org 0x0000
    jmp reset

.org PCI0addr
    jmp pcint0_isr

.org OC1Aaddr
    jmp OCI1A_ISR


reset:
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

    ; Inicializa UART
    ldi temp1, 103          ; Baudrate 9600 (para 16 MHz e UBRR = 103)
    sts UBRR0L, temp1
    ldi temp1, (1 << TXEN0) ; Habilita transmissor
    sts UCSR0B, temp1
    ldi temp1, (1 << UCSZ01) | (1 << UCSZ00) ; 8 bits
    sts UCSR0C, temp1


    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16


	;ldi temp1, 0b00001111     ; PB0–PB3 como saída
	ldi temp1, 0b00011111     ; PB0–PB4 como saída
	out DDRB, temp1

	
    



    ldi temp1, 0              ; Carrega o valor 0 no registrador temp1 (r16)


	sts mode_1, temp1         ; Zera os minutos atuais do relógio (mode_1 = 0)
	sts mode_1 + 1, temp1     ; Zera os segundos atuais do relógio (mode_1 + 1 = 0)
	sts mode_2, temp1         ; Zera os minutos do cronômetro (mode_2 = 0)
	sts mode_2 + 1, temp1     ; Zera os segundos do cronômetro (mode_2 + 1 = 0)
	sts mode_2 + 2, temp1     ; Zera a flag de ativação do cronômetro (mode_2 + 2 = 0)


    ldi temp1, (1 << OCIE1A)  ; Carrega no registrador temp1 um valor com o bit OCIE1A ativado (bit que habilita a interrupção do Timer1 Compare Match A)
	sts TIMSK1, temp1         ; Escreve esse valor no registrador TIMSK1, ativando a interrupção do Timer1 (Canal A)


    .equ PRESCALE = 0b100           ; Seleciona o prescaler do Timer1 como 256 (CS12:CS10 = 100)
	.equ PRESCALE_DIV = 256         ; Valor real do prescaler (divisor de clock)
	.equ WGM = 0b0100               ; Define o modo de operação do Timer1 como CTC (Clear Timer on Compare Match)
	.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
									 ; Calcula o valor de contagem necessário para gerar uma interrupção a cada DELAY segundos
									 ; Fórmula: TOP = (Clock / Prescaler) * Tempo
									 ; Exemplo: (16.000.000 / 256) * 1s = 62500 → TOP = 62500
									 ; Esse valor será colocado em OCR1A


	ldi temp1, high(TOP)              ; Carrega o byte mais significativo do valor TOP no registrador temp1
	sts OCR1AH, temp1                 ; Armazena esse valor no registrador OCR1AH (parte alta do valor de comparação do Timer1)
	ldi temp1, low(TOP)               ; Carrega o byte menos significativo do valor TOP no registrador temp1
	sts OCR1AL, temp1                 ; Armazena esse valor no registrador OCR1AL (parte baixa do valor de comparação do Timer1)
									  ; Agora OCR1A = TOP, valor que define quando o timer gera uma interrupção (em modo CTC)

	ldi temp1, ((WGM & 0b11) << WGM10) ; Extrai os 2 bits menos significativos de WGM e posiciona em WGM10/WGM11
	sts TCCR1A, temp1                 ; Configura os bits de modo de operação do Timer1 no registrador TCCR1A

	ldi temp1, ((WGM >> 2) << WGM12) | (PRESCALE << CS10)
									  ; Extrai os bits mais significativos de WGM e o valor do prescaler,
									  ; desloca para as posições corretas (WGM12/WGM13 e CS10/CS11/CS12)

	sts TCCR1B, temp1                 ; Configura modo CTC e ativa o prescaler de 256 no registrador TCCR1B
	ldi actual_mode, 2                ; Define o modo de operação inicial como 2 (cronômetro ativo)
	sei                               ; Ativa as interrupções globais (sem isso, nenhuma interrupção é executada)


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
    rjmp ligar

    ; Botão solto → desliga PB4
    cbi PORTB, PB4
    rjmp pcint0_isr

ligar:
    ; Botão pressionado → liga PB4
    sbi PORTB, PB4

pcint0_isr:
    pop r16
    reti


OCI1A_ISR:
    push r16                 ; Salva registrador temporário
    in r16, SREG
    push r16                 ; Salva o status do processador (flags)

    cpi actual_mode, 2       ; Se o modo atual for cronômetro (2)
    brne continue            ; Se não for, pula
    rcall cronometro         ; Chama função do cronômetro

	continue:
		cpi actual_mode, 3       ; Se for modo ajuste (3), pula
		breq pass
		rcall hora_atual         ; Atualiza o relógio

	pass:
		pop r16                  ; Restaura SREG
		out SREG, r16
		pop r16                  ; Restaura r16
		reti                     ; Retorna da interrupção


hora_atual:
    push temp1               ; Salva registradores temporários
    push temp2

    lds temp2, mode_1 + 1    ; Carrega segundos atuais do relógio
    inc temp2                ; Incrementa 1 segundo

    cpi temp2, 60            ; Verifica se chegou a 60 segundos
    breq atualiza_minuto_atual ; Se sim, pula para atualizar minutos

    sts mode_1 + 1, temp2    ; Caso contrário, salva segundos atualizados
    rjmp end                 ; E sai da função

    atualiza_minuto_atual:
		lds temp1, mode_1        ; Carrega minutos atuais
		inc temp1                ; Incrementa minutos
		sts mode_1, temp1        ; Salva minutos atualizados

		ldi temp2, 0             ; Zera os segundos
		sts mode_1 + 1, temp2

    end:
    pop temp1                ; Restaura registradores
    pop temp2
    ret                      ; Retorna da função


cronometro:
    push temp1               ; Salva registradores temporários
    push temp2

    lds temp2, mode_2 + 2    ; Lê a flag de ativação do cronômetro
    cpi temp2, 0
    breq pass_soma           ; Se for 0, cronômetro está desligado → sai da função

    lds temp2, mode_2 + 1    ; Lê os segundos do cronômetro
    inc temp2                ; Incrementa 1 segundo

    cpi temp2, 60
    breq atualiza_minuto_cronometro ; Se chegou a 60 segundos, vai atualizar minutos

    sts mode_2 + 1, temp2    ; Caso contrário, salva os segundos atualizados

	atualiza_minuto_cronometro:
		lds temp1, mode_2        ; Lê os minutos
		inc temp1                ; Incrementa minutos
		sts mode_2, temp1        ; Salva minutos atualizados

		ldi temp2, 0             ; Zera os segundos
		sts mode_2 + 1, temp2

	pass_soma:
		pop temp1                ; Restaura registradores
		pop temp2
		ret                      ; Retorna da função


exibe_digito_0:
    lds temp1, mode_1 + 1
    ldi temp2, 10
    call dividir             ; temp1 = quociente, temp2 = resto
    mov temp1, temp2         ; unidade dos segundos
    rcall enviar_para_cd4511

    in temp2, PORTB
    sbrc temp2, PB4          ; se PB4 está alto
        ori temp2, (1 << PB4) ; preserva PB4
    andi temp2, 0b11110000   ; limpa PB0–PB3
    ori temp2, (1 << PB3)    ; ativa display 0
    out PORTB, temp2
    ret


exibe_digito_1:
    lds temp1, mode_1 + 1
    ldi temp2, 10
    call dividir             ; temp1 = dezena dos segundos
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
    call dividir             ; temp1 = dezena, temp2 = unidade dos minutos
    mov temp1, temp2         ; queremos a unidade
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
    call dividir             ; temp1 = dezena dos minutos
    rcall enviar_para_cd4511

    in temp2, PORTB
    sbrc temp2, PB4
    ori temp2, (1 << PB4)
    andi temp2, 0b11110000
    ori temp2, (1 << PB0)
    out PORTB, temp2
    ret




enviar_para_cd4511:
    lsl temp1        ; <<1
    lsl temp1        ; <<2 → desloca para alinhar com PD2–PD5

    in temp2, PORTD
    andi temp2, 0b11000011   ; limpa bits PD2–PD5
    or temp2, temp1
    out PORTD, temp2
    ret


dividir:
    push r19

    clr r19              ; r19 será o quociente
div_loop:
    cp temp1, temp2      ; compara se temp1 >= temp2
    brlo fim_div         ; se temp1 < temp2, fim

    sub temp1, temp2     ; temp1 -= temp2
    inc r19              ; quociente++

    rjmp div_loop

fim_div:
    mov temp2, temp1     ; resto → temp2
    mov temp1, r19       ; quociente → temp1

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

