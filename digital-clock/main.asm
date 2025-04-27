.include "m328pdef.inc"              ; Inclui as definições do ATmega328P (endereços, registradores, etc.)

; Define constantes
#define CLOCK 16000000                ; Define a frequência do clock em 16 MHz
#define DELAY 1                       ; Define o atraso (delay) em 1 (unidade arbitrária)
#define BAUD 9600                     ; Define a taxa de transmissão serial em 9600 baud
.equ UBRR_VALUE = 103                ; Define o valor do UBRR para configurar a baud rate

; Define a origem da RAM para a seção de dados (variáveis)
.org 0x200
.INCLUDE "modes.asm"                ; Inclui funções relacionadas aos modos de operação (relógio, cronômetro, etc.)
.INCLUDE "display.asm"              ; Inclui funções relacionadas ao display multiplexado
.INCLUDE "uart.asm"                 ; Inclui funções relacionadas à comunicação UART (serial)

; ============================
; Definição de Registradores (Aliases para registradores)
; ============================
.def zero = r1                     ; Registrador r1 sempre contém zero (padronizado para cálculos, por exemplo, ADC)
.def actual_mode = r18             ; Armazena o modo atual de operação (1: relógio, 2: cronômetro, 3: ajuste, etc.)
.def temp1 = r16                	  ; Registrador temporário para operações gerais
.def temp2 = r17                	  ; Outro registrador temporário
.def temp3  = r20                  ; Registrador temporário adicional
.def tx_byte = r19                 ; Armazena o byte a ser transmitido pela comunicação serial
.def byte_val = r21                ; Armazena um byte que será convertido para seu equivalente ASCII em decimal
.def ascii_H = r22                 ; Guarda o dígito ASCII da dezena
.def ascii_L = r23                 ; Guarda o dígito ASCII da unidade
.def botao_pd7 = r24               ; Registrador para controle do botão ligado ao pino PD7

; ============================
; Área de Dados (declaração de variáveis em RAM)
; ============================
.dseg
mode_1: .byte 2                   ; Variável para o modo 1 (ex.: relógio) que armazena 2 bytes (minutos e segundos)
mode_2: .byte 3                   ; Variável para o modo 2 (ex.: cronômetro) que armazena 3 bytes (min, seg e flag de ativação)
adjust_digit_selector: .byte 1    ; Seletor para ajuste de dígitos no MODO 3 (0 = seg unidade, 1 = seg dezena, 2 = min unidade, 3 = min dezena)
trocar_modo_flag: .byte 1         ; Flag para sinalizar troca de modo (utilizado para debouncing ou controle)
blink_counter: .byte 1            ; Contador utilizado para controlar a piscagem (blink) do display ou indicador

; ============================
; Área de Código (instruções principais e vetores de interrupção)
; ============================
.cseg
; ============================
; Vetores de Interrupção
; ============================
.org 0x0000
    jmp reset                    ; Vetor de Reset: salta para a rotina "reset"

.org PCI0addr
    jmp pcint0_isr               ; Vetor da interrupção em PCINT0 (associado ao pino PB5)

.org PCI2addr
    jmp pcint2_isr               ; Vetor da interrupção em PCINT2 (associado aos pinos PD6 e PD7)

.org OC1Aaddr
    jmp OCI1A_ISR                ; Vetor da interrupção do Timer1 Compare Match A

.org UDREaddr
    jmp uart_udre_isr            ; Vetor da interrupção de UDR (Transmissor UART pronto para enviar novo byte)

; --- Strings para a Comunicação Serial ---
str_modo1: .db "[MODO 1] ", 0                   ; String identificando o modo 1 (Relógio)
str_modo2_run: .db "[MODO 2] RUN ", 0             ; String identificando o modo 2 em execução (Cronômetro em contagem)
str_modo2_stop: .db "[MODO 2] STOPPED ", 0        ; String identificando o modo 2 parado (Cronômetro parado)
str_modo2_zero: .db "[MODO 2] ZERO", 0            ; String identificando o modo 2 zerado
str_modo3_su: .db "[MODO 3] Ajustando a unidade dos segundos", 0   ; String para MODO 3, ajuste do dígito dos segundos (unidade)
str_modo3_sd: .db "[MODO 3] Ajustando a dezena dos segundos ", 0     ; String para MODO 3, ajuste do dígito dos segundos (dezena)
str_modo3_mu: .db "[MODO 3] Ajustando a unidade dos minutos ", 0     ; String para MODO 3, ajuste do dígito dos minutos (unidade)
str_modo3_md: .db "[MODO 3] Ajustando a dezena dos minutos", 0       ; String para MODO 3, ajuste do dígito dos minutos (dezena)
str_colon: .db ":", 0                           ; String contendo dois pontos para separação (ex.: no relógio)
str_newline: .db "\r\n ", 0                      ; String para quebra de linha (Carriage Return e Line Feed)

; ============================
; Rotina de Reset (inicialização do sistema)
; ============================
reset:
	; --- Inicialização das Variáveis ---
    ldi temp1, 0                 ; Carrega o valor 0 no registrador temp1 (r16)
	sts mode_1, temp1            ; Zera a variável mode_1 (minutos do relógio)
	sts mode_1 + 1, temp1        ; Zera o segundo byte de mode_1 (segundos do relógio)
	sts mode_2, temp1            ; Zera a variável mode_2 (minutos do cronômetro)
	sts mode_2 + 1, temp1        ; Zera o primeiro byte de segundos do cronômetro
	sts mode_2 + 2, temp1        ; Zera a flag de ativação do cronômetro
    sts adjust_digit_selector, temp1 ; Zera o seletor de ajuste para o MODO 3

	; --- Configuração do PORTB (PB0 a PB4 como saída) ---
	ldi temp1, 0b00011111        ; Configura os bits PB0 a PB4 como 1 para serem saídas
	out DDRB, temp1              ; Escreve a configuração no registrador DDRB

    ; --- Configuração do PORTD (PD0 a PD5 como saída) ---
    ldi temp1, 0b00111100
	out DDRD, temp1

    ; --- Configuração dos pinos PD6 e PD7 como entradas com pull-up ---
    in temp1, DDRD            	  ; Lê a direção do PORTD
    andi temp1, ~(1 << PD6 | 1 << PD7)  ; Limpa os bits de PD6 e PD7 para configurar como entrada
    out DDRD, temp1              ; Atualiza DDRD com PD6 e PD7 como entrada

    in temp1, PORTD              ; Lê o valor atual de PORTD
    ori temp1, (1 << PD6 | 1 << PD7) ; Ativa os resistores de pull-up para PD6 e PD7
    out PORTD, temp1             ; Escreve a configuração atualizada em PORTD

    ; --- Configuração do pino PB5 como entrada com pull-up ---
    in temp1, DDRB            	  ; Lê a configuração atual do PORTB
    andi temp1, ~(1 << PB5)      ; Configura PB5 como entrada (limpa bit correspondente)
    out DDRB, temp1              ; Atualiza DDRB com PB5 como entrada

    in temp1, PORTB              ; Lê o valor atual de PORTB
    ori temp1, (1 << PB5)        ; Ativa o resistor de pull-up para PB5
    out PORTB, temp1             ; Escreve a configuração atualizada em PORTB

    ; --- Configuração das interrupções de PCINT para PD6 e PD7 ---
    ldi temp1, (1 << PCINT22) | (1 << PCINT23) ; Prepara a máscara para habilitar interrupções em PD6 (PCINT22) e PD7 (PCINT23)
    sts PCMSK2, temp1            ; Escreve a máscara no registrador PCMSK2

    ; --- Configuração da interrupção de PCINT para PB5 ---
    ldi temp1, (1 << PCINT5)     ; Configura a máscara para habilitar interrupção no PB5 (PCINT5)
    sts PCMSK0, temp1            ; Escreve a máscara no registrador PCMSK0

    ; --- Ativação dos grupos de interrupção PCINT ---
    ldi temp1, (1 << PCIE2) | (1 << PCIE0)  ; Habilita os grupos de interrupção PCINT2 (PORTD) e PCINT0 (PORTB)
    sts PCICR, temp1             ; Escreve a configuração no registrador PCICR

	; --- Configuração do Timer1 ---
    ldi temp1, (1 << OCIE1A)     ; Habilita a interrupção de Compare Match A do Timer1 (bit OCIE1A)
	sts TIMSK1, temp1            ; Escreve em TIMSK1 para ativar a interrupção do Timer1

    .equ PRESCALE = 0b100        ; Define que o prescaler é 256 (CS12:CS10 = 100)
	.equ PRESCALE_DIV = 256       ; Valor numérico do divisor do prescaler
	.equ WGM = 0b0100             ; Define o modo de operação CTC (Clear Timer on Compare Match)
	.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY)) ; Calcula o valor de comparação para gerar um atraso definido

	ldi temp1, high(TOP)         ; Carrega o byte mais significativo do valor TOP em temp1
	sts OCR1AH, temp1            ; Armazena o byte alto no registrador OCR1AH
	ldi temp1, low(TOP)          ; Carrega o byte menos significativo do valor TOP em temp1
	sts OCR1AL, temp1            ; Armazena o byte baixo no registrador OCR1AL
	ldi temp1, ((WGM & 0b11) << WGM10) ; Prepara os 2 bits menos significativos de WGM para configurar TCCR1A
	sts TCCR1A, temp1            ; Configura TCCR1A com o modo CTC
	ldi temp1, ((WGM >> 2) << WGM12) | (PRESCALE << CS10) ; Configura TCCR1B para o modo CTC e ativa o prescaler
	sts TCCR1B, temp1            ; Escreve em TCCR1B a configuração do Timer1

	; --- Configuração da Comunicação Serial (UART) ---
	ldi temp1, high(UBRR_VALUE)  ; Carrega o byte alto do valor UBRR (taxa de baud)
	sts UBRR0H, temp1           ; Configura o registrador UBRR0H para UART
	ldi temp1, low(UBRR_VALUE)   ; Carrega o byte baixo do valor UBRR
	sts UBRR0L, temp1           ; Configura o registrador UBRR0L
	ldi temp1, (1 << TXEN0) | (1 << UDRIE0)  ; Habilita a transmissão (TX) e a interrupção do UDR da UART
	sts UCSR0B, temp1           ; Escreve a configuração no registrador UCSR0B
	ldi temp1, (1 << UCSZ01) | (1 << UCSZ00)  ; Configura o formato dos dados: 8 bits, sem paridade, 1 stop bit
	sts UCSR0C, temp1           ; Escreve a configuração no registrador UCSR0C

    ; --- Estado Inicial do Sistema ---
    ldi actual_mode, 1         ; Define o modo inicial como 1 (Relógio)
    sei                        ; Habilita as interrupções globais

; ============================
; Loop Principal
; ============================
main_loop:
	rcall multiplexar_display   ; Chama a rotina que atualiza o display multiplexado
    rjmp main_loop              ; Salta incondicionalmente para o início do loop principal

; ============================
; ISR: PCINT2 (Interrupção para PD6 e PD7)
; ============================
pcint2_isr:
    push temp1                ; Salva o conteúdo de r16
    push temp2                ; Salva o conteúdo de r17
    push temp3                ; Salva o conteúdo de r20
    in temp1, SREG            ; Lê o registrador de status (SREG)
    push temp1                ; Salva o SREG

    in temp2, PIND            ; Lê o valor dos pinos do PORTD
    sbrc temp2, PD6           ; Se o bit PD6 estiver limpo (descida), pula a próxima instrução
    rjmp verifica_pd7         ; Caso contrário, pula para verificar PD7
    ldi temp3, 5              ; Inicializa um contador para debouncing

; --- Rotina de verificação para PD6 (detecção de borda de descida) ---
verifica_pd6:
    in temp1, PIND            ; Lê novamente o estado de PORTD
    sbrc temp1, PD6           ; Verifica se PD6 ainda está ativo (alta), se sim pula
    rjmp verifica_pd7         ; Se mudou, passa a verificar PD7
    dec temp3                 ; Decrementa o contador
    brne verifica_pd6         ; Se o contador não zerou, repete a verificação

	;; Ação executada se PD6 confirma uma borda de descida:
	; Se o modo atual é 2 (cronômetro), executa o reset do modo 2
	cpi actual_mode, 2        
	brne checa_reset_modo3     ; Se não for modo 2, pula para verificação do modo 3
	rcall handle_reset_modo2   ; Chama a rotina para resetar o cronômetro (modo 2)
	rjmp fim_acao_pd6         ; Salta para o fim da ação de PD6

checa_reset_modo3:
	; Se o modo atual é 3 (ajuste), executa o reset do modo 3
	cpi actual_mode, 3
	brne fim_acao_pd6         ; Se não for modo 3, não faz nada
	rcall handle_reset_modo3   ; Chama a rotina para reset do modo 3

fim_acao_pd6:
    ; --- Continuação: Verificação para PD7 ---
; --- Rotina de verificação para PD7 (detecção de borda de descida) ---
verifica_pd7:
    in temp2, PIND            ; Lê o valor atual dos pinos de PORTD
    sbrc temp2, PD7           ; Se PD7 estiver em nível lógico alto, pula
    rjmp end_pcint2_isr       ; Se não, prossegue com a detecção de borda de descida
    ldi temp3, 5              ; Inicializa o contador para debouncing de PD7

verifica_pd7_loop:
    in temp1, PIND            ; Lê novamente o PORTD
    sbrc temp1, PD7           ; Verifica o estado de PD7; se ainda estiver ativo, pula
    rjmp end_pcint2_isr       ; Se já subiu, sai da rotina
    dec temp3                 ; Decrementa o contador
    brne verifica_pd7_loop    ; Repete enquanto o contador não chegar a zero

	;; Ação executada se PD7 confirma a borda de descida:
	; Se o modo atual é 2, executa a ação de início do cronômetro
	cpi actual_mode, 2
	brne pass_start_modo2     ; Se não for modo 2, verifica o modo 3
	rcall beep_modo            ; Emite um beep para sinalizar a ação
	rcall handle_start_modo2   ; Chama a rotina para iniciar o cronômetro (modo 2)
	rjmp pass_start_modo3     ; Pula para a verificação seguinte

	pass_start_modo2:
	cpi actual_mode, 3
	brne pass_start_modo3     ; Se não for modo 3, não faz ação
	rcall handle_start_modo3   ; Chama a rotina para iniciar a ação específica do modo 3

	pass_start_modo3:
    ; --- Finalização da ISR PCINT2 ---
end_pcint2_isr:
    pop temp1                 ; Restaura o valor salvo do SREG
    out SREG, temp1           ; Restaura o SREG

    pop temp3                 ; Restaura temp3
    pop temp2                 ; Restaura temp2
    pop temp1                 ; Restaura temp1
    reti                      ; Retorna da interrupção

; ============================
; ISR: PCINT0 (Interrupção para PB5)
; ============================
pcint0_isr:
    push temp1                ; Salva r16
    push temp2                ; Salva r17
    push temp3                ; Salva r20
    in temp1, SREG            ; Lê o SREG
    push temp1                ; Salva o SREG

    in temp2, PINB            ; Lê o valor dos pinos de PORTB
    sbrc temp2, PB5           ; Se PB5 estiver alto, pula a próxima instrução
    rjmp end_isr              ; Se o botão não foi pressionado, sai da ISR
    ldi temp3, 5              ; Inicializa contador para debouncing

verifica_pb5:
    in temp1, PINB            ; Lê novamente o PINB
    sbrc temp1, PB5           ; Verifica se PB5 mudou de estado
    rjmp end_isr              ; Se o botão não estiver mais pressionado, termina a verificação
    dec temp3                 ; Decrementa o contador
    brne verifica_pb5         ; Repete a verificação enquanto o contador não chegar a zero

    ;; Ação executada na interrupção:
	rcall beep_modo            ; Emite um beep para indicar a mudança de modo
    inc actual_mode           ; Incrementa o modo atual
    cpi actual_mode, 4        ; Compara se o novo modo atingiu 4
    brne end_isr              ; Se não for 4, termina a ISR
    ldi actual_mode, 1        ; Se for 4, reinicia para o modo 1 (relógio)

end_isr:
    pop temp1                 ; Restaura o SREG
    out SREG, temp1           ; Restaura o SREG

    pop temp3                 ; Restaura temp3
    pop temp2                 ; Restaura temp2
    pop temp1                 ; Restaura temp1
    reti                      ; Retorna da interrupção

; ============================
; ISR: Timer1 Compare Match A (rotina executada a cada segundo)
; ============================
OCI1A_ISR:
    ; --- Salvar contexto ---
    push temp1                ; Salva r16
    push temp2                ; Salva r17
    push temp3                ; Salva r20
    in temp1, SREG            ; Lê SREG
    push temp1                ; Salva SREG

    ; --- Lógica de atualização do tempo ---
    cpi actual_mode, 3        ; Compara se o modo atual é 3 (modo de ajuste)
    breq passa_hora           ; Se for modo 3, pula a atualização do relógio
    rcall hora_atual          ; Caso contrário, atualiza a hora (rotina que incrementa o relógio)

passa_hora:
	; --- Se o cronômetro estiver ativado (flag em mode_2 + 2 = 1), atualiza o cronômetro ---
	lds temp1, mode_2 + 2      ; Carrega o valor da flag do cronômetro
	cpi temp1, 1              ; Verifica se a flag está ativa (igual a 1)
	brne pass_cronometro      ; Se não estiver ativa, pula a rotina de cronômetro
    rcall cronometro          ; Se estiver ativa, chama a rotina que atualiza o cronômetro
pass_cronometro:

    ; --- Envio de informações via UART conforme o modo ---
    cpi actual_mode, 1        ; Verifica se o modo atual é 1 (Relógio)
	brne pass_uart_mode1
    rcall send_mode1          ; Se for modo 1, envia informações do relógio pela serial
pass_uart_mode1:

    cpi actual_mode, 2        ; Verifica se o modo atual é 2 (Cronômetro)
	brne pass_uart_mode2
    rcall send_mode2          ; Se for modo 2, envia informações do cronômetro pela serial
pass_uart_mode2:

    cpi actual_mode, 3        ; Verifica se o modo atual é 3 (Ajuste)
    brne continuar_uart       ; Se não for modo 3, pula para continuar
    rcall send_mode3          ; Se for modo 3, envia informações de ajuste pela serial

continuar_uart:
isr_end:
    ; --- Restaurar contexto ---
    pop temp1                 ; Restaura SREG
    out SREG, temp1           ; Restaura SREG
    pop temp3                 ; Restaura temp3
    pop temp2                 ; Restaura temp2
    pop temp1                 ; Restaura temp1
    reti                      ; Retorna da interrupção

; ============================
; Função: beep_modo
; Descrição: Emite um beep através do pino PB4 para indicar uma mudança ou ação de modo
; ============================
beep_modo:
    sbi PORTB, PB4            ; Liga o buzzer
    rcall delay_beep          ; Delay grande específico para beep
    cbi PORTB, PB4            ; Desliga o buzzer
    ret



; ============================
; Função de delay para o beep do buzzer
; ============================
delay_beep:
    push r24
    push r25
    ldi r25, high(50000)      ; Valor muito maior que o delay_multiplex
    ldi r24, low(50000)
delay_beep_loop:
    sbiw r24, 1
    brne delay_beep_loop
    pop r25
    pop r24
    ret
