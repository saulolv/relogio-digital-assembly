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
trocar_modo_flag: .byte 1


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


    in temp1, PORTD
    ori temp1, (1 << PD6) | (1 << PD7)
    out PORTD, temp1

    ; Ativa pull-up em PD6 (RESET) e PD7 (START)
    in temp1, DDRD
    andi temp1, 0b00111111     ; PD6 e PD7 como entrada
    out DDRD, temp1

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
    ; Verifica flag de troca de modo
    lds temp1, trocar_modo_flag
    cpi temp1, 1
    brne verificar_botoes

    ; Beep e troca de modo
    rcall beep_modo
    rcall trocar_modo

; CONTROLE DE MODO E VERIFICAÇÃO DE BOTÕES
; ============================
verificar_botoes:
    ; Verifica qual modo está ativo para chamar a rotina apropriada
    cpi actual_mode, 2           ; Compara o modo atual com 2
    breq handle_modo2            ; Se for modo 2, pula para handle_modo2
    cpi actual_mode, 3           ; Compara o modo atual com 3
    breq handle_modo3            ; Se for modo 3, pula para handle_modo3
    rjmp continuar               ; Se não for modo 2 nem 3, pula para continuar

handle_modo2:
    rcall verifica_botoes_modo2  ; Chama a rotina de verificação de botões do modo 2
    rjmp continuar               ; Pula para continuar após verificar

handle_modo3:
    rcall verifica_botoes_modo3  ; Chama a rotina de verificação de botões do modo 3
    rjmp continuar               ; Pula para continuar após verificar

continuar:
    ; Multiplexação diferente para o modo 3 (com efeito de piscar)
    cpi actual_mode, 3           ; Verifica se está no modo 3
    breq multiplex_modo3         ; Se for modo 3, usa multiplexação com efeito de piscar
    rcall multiplexar_display    ; Se não for modo 3, usa multiplexação normal
    rjmp main                    ; Retorna para o início do loop principal

multiplex_modo3:
    rcall multiplexar_display_modo3 ; Chama a rotina de multiplexação especial para modo 3
    rjmp main                     ; Retorna para o início do loop principal



verifica_botoes_modo3:
    ; Verifica se o botão START (PD7) foi pressionado para navegar entre os dígitos
    sbic PIND, PD7          ; Se o bit PD7 estiver limpo (botão pressionado), prossegue
    rjmp verifica_reset_modo3 ; Caso contrário, pula para verificar o botão RESET
    rcall navegar_digitos    ; Se START foi pressionado, aciona a rotina de navegação
    rcall beep_modo         ; Emite beep para indicar a ação
esperar_soltar_start_modo3:
    sbis PIND, PD7          ; Aguarda que o botão START seja solto
    rjmp esperar_soltar_start_modo3

verifica_reset_modo3:
    ; Verifica se o botão RESET (PD6) foi pressionado para ajustar o valor do dígito selecionado
    sbic PIND, PD6          ; Se o bit PD6 estiver limpo (pressionado), prossegue
    rjmp fim_verificacao_botoes_modo3 ; Se não, pula para o fim da verificação
    rcall ajustar_digito    ; Se RESET for pressionado, chama a rotina de ajuste
    rcall beep_modo         ; Emite beep para indicar a ação
esperar_soltar_reset_modo3:
    sbis PIND, PD6          ; Aguarda que o botão RESET seja solto
    rjmp esperar_soltar_reset_modo3

fim_verificacao_botoes_modo3:
    ret                     ; Retorna da função

; ============================================================
; FUNÇÃO: navegar_digitos
; Finalidade: Avança para o próximo dígito a ser ajustado no Modo 3
; ============================================================
navegar_digitos:
    lds temp1, adjust_digit_selector  ; Carrega o valor atual do seletor de dígitos
    inc temp1                        ; Incrementa para o próximo dígito
    cpi temp1, 4                     ; Verifica se chegou ao limite (4 dígitos: 0,1,2,3)
    brlo salvar_digito_atual         ; Se for menor que 4, salva o novo valor
    ldi temp1, 0                     ; Se chegou a 4, volta para o primeiro dígito (0)
salvar_digito_atual:
    sts adjust_digit_selector, temp1  ; Salva o novo valor do seletor de dígitos

    ; Envia mensagem de navegação conforme o dígito selecionado
    cpi temp1, 0
    breq envia_msg_su
    cpi temp1, 1
    breq envia_msg_sd
    cpi temp1, 2
    breq envia_msg_mu
    cpi temp1, 3
    breq envia_msg_md
    ret                              ; Retorna da função em caso de valor inválido

envia_msg_su:
    ldi ZL, low(str_modo3_su<<1)     ; Prepara a string "Ajustando a unidade dos segundos"
    ldi ZH, high(str_modo3_su<<1)
    rcall USART_Transmit_String
    rjmp enviar_nl_fin_dig
envia_msg_sd:
    ldi ZL, low(str_modo3_sd<<1)     ; Prepara a string "Ajustando a dezena dos segundos"
    ldi ZH, high(str_modo3_sd<<1)
    rcall USART_Transmit_String
    rjmp enviar_nl_fin_dig
envia_msg_mu:
    ldi ZL, low(str_modo3_mu<<1)     ; Prepara a string "Ajustando a unidade dos minutos"
    ldi ZH, high(str_modo3_mu<<1)
    rcall USART_Transmit_String
    rjmp enviar_nl_fin_dig
envia_msg_md:
    ldi ZL, low(str_modo3_md<<1)     ; Prepara a string "Ajustando a dezena dos minutos"
    ldi ZH, high(str_modo3_md<<1)
    rcall USART_Transmit_String

enviar_nl_fin_dig:
    ldi ZL, low(str_newline<<1)      ; Prepara string de nova linha
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String
    ret                              ; Retorna da função

; Funções de ajuste corrigidas para o modo 3
; ============================================================
; FUNÇÃO: ajustar_digito
; Finalidade: Ajusta o valor do dígito selecionado no Modo 3
; ============================================================
ajustar_digito:
    lds temp1, adjust_digit_selector  ; Carrega o seletor de dígitos atual
    cpi temp1, 0                      ; Verifica qual dígito está selecionado
    breq ajustar_su                   ; Unidade dos segundos
    cpi temp1, 1
    breq ajustar_sd                   ; Dezena dos segundos
    cpi temp1, 2
    breq ajustar_mu                   ; Unidade dos minutos
    cpi temp1, 3
    breq ajustar_md                   ; Dezena dos minutos
    ret                               ; Retorna se valor inválido

ajustar_su:
    ; Ajusta a unidade dos segundos
    lds temp1, mode_1 + 1             ; Carrega os segundos atuais
    ldi temp2, 10
    rcall dividir                     ; temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade
    cpi temp2, 10                     ; Verifica se passou de 9
    brlo salvar_su                    ; Se não passou, salva
    ldi temp2, 0                      ; Se passou, volta para 0
salvar_su:
    ; Recalcula o valor binário: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = dezena * 10
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1 + 1, temp1             ; Salva o novo valor dos segundos
    ret

ajustar_sd:
    ; Ajusta a dezena dos segundos
    lds temp1, mode_1 + 1             ; Carrega os segundos atuais
    ldi temp2, 10
    rcall dividir                     ; temp1 = dezena, temp2 = unidade
    inc temp1                         ; Incrementa a dezena
    cpi temp1, 6                      ; Verifica se passou de 5
    brlo salvar_sd                    ; Se não passou, salva
    ldi temp1, 0                      ; Se passou, volta para 0
salvar_sd:
    ; Recalcula o valor binário: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = dezena * 10
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1 + 1, temp1             ; Salva o novo valor dos segundos
    ret

ajustar_mu:
    ; Ajusta a unidade dos minutos
    lds temp1, mode_1                 ; Carrega os minutos atuais
    ldi temp2, 10
    rcall dividir                     ; temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade
    cpi temp2, 10                     ; Verifica se passou de 9
    brlo salvar_mu                    ; Se não passou, salva
    ldi temp2, 0                      ; Se passou, volta para 0
salvar_mu:
    ; Recalcula o valor binário: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = dezena * 10
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1, temp1                 ; Salva o novo valor dos minutos
    ret

ajustar_md:
    ; Ajusta a dezena dos minutos
    lds temp1, mode_1                 ; Carrega os minutos atuais
    ldi temp2, 10
    rcall dividir                     ; temp1 = dezena, temp2 = unidade
    inc temp1                         ; Incrementa a dezena
    cpi temp1, 6                      ; Verifica se passou de 5
    brlo salvar_md                    ; Se não passou, salva
    ldi temp1, 0                      ; Se passou, volta para 0
salvar_md:
    ; Recalcula o valor binário: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = dezena * 10
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1, temp1                 ; Salva o novo valor dos minutos
    ret
; ============================================================
; FUNÇÃO: multiplexar_display_modo3
; Finalidade: Multiplexação do display com efeito de piscar no dígito selecionado (Modo 3)
; ============================================================
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

    ; Verifica o contador de pisca para criar efeito de piscada
    in temp1, TCNT0          ; Usa o contador do Timer0 como base para piscar
    andi temp1, 0x80         ; Usa o bit mais significativo para alternar (~2Hz)
    breq exibe_normal        ; Se for 0, exibe normal

	ldi temp1, (1 << CS02) | (0 << CS01) | (1 << CS00)  ; Prescaler = 1024
    out TCCR0B, temp1                                   ; Configura o Timer0
    ldi temp1, 0                                         ; Inicializa o contador
    out TCNT0, temp1                                     ; Zera o contador do Timer0

    
    ; Se for 1, apaga o dígito selecionado (efeito de piscar)
    lds temp1, adjust_digit_selector
    cpi temp1, 0              ; Verifica qual dígito está selecionado
    breq apaga_su             ; Unidade dos segundos
    cpi temp1, 1
    breq apaga_sd             ; Dezena dos segundos
    cpi temp1, 2
    breq apaga_mu             ; Unidade dos minutos
    cpi temp1, 3
    breq apaga_md             ; Dezena dos minutos
    rjmp exibe_normal         ; Se não for nenhum, exibe normal

apaga_su:
    ldi r23, 10              ; Valor 10 não será exibido (apaga)
    rjmp exibe_normal
apaga_sd:
    ldi r24, 10              ; Apaga dezena dos segundos
    rjmp exibe_normal
apaga_mu:
    ldi r25, 10              ; Apaga unidade dos minutos
    rjmp exibe_normal
apaga_md:
    ldi r26, 10              ; Apaga dezena dos minutos

exibe_normal:
    ; Exibe cada dígito
    mov temp1, r23           ; Unidade dos segundos
    cpi temp1, 10            ; Verifica se é para apagar (valor 10)
    breq desliga_display_su  ; Se for 10, desliga esse dígito
    rcall enviar_para_cd4511 ; Senão, envia para o display
    in temp2, PORTB
    andi temp2, 0b11110000   ; Zera os 4 bits inferiores
    ori temp2, (1 << PB3)    ; Ativa o display da unidade dos segundos (PB3)
    out PORTB, temp2
    rjmp continua_sd

desliga_display_su:
    in temp2, PORTB          ; Lê PORTB
    andi temp2, 0b11110111   ; Desliga o bit PB3 (apaga o display)
    out PORTB, temp2

continua_sd:
    rcall delay_multiplex    ; Delay para estabilização

    mov temp1, r24           ; Dezena dos segundos
    cpi temp1, 10            ; Verifica se é para apagar
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


; --- Função: Emitir beep curto (PB4) ---
beep_modo:
    sbi PORTB, PB4
    rcall delay_multiplex
    cbi PORTB, PB4
    ret


; --- Função: Trocar modo atual (1 → 2 → 3 → 1) ---
trocar_modo:
    mov temp1, actual_mode
    inc temp1
    cpi temp1, 4
    brlo modo_ok
    ldi temp1, 1
modo_ok:
    mov actual_mode, temp1
    ldi temp1, 0
    sts trocar_modo_flag, temp1
    ret



; --- Função: Verificar botões START (PD7) e RESET (PD6) ---
verifica_botoes_modo2:
    ; Verifica botão START (PD7)
    sbic PIND, PD7
    rjmp verifica_reset
    rcall aciona_start
esperar_soltar_start:
    sbis PIND, PD7
    rjmp esperar_soltar_start

verifica_reset:
    ; Verifica botão RESET (PD6)
    sbic PIND, PD6
    rjmp fim_verifica_botoes
    rcall aciona_reset
esperar_soltar_reset:
    sbis PIND, PD6
    rjmp esperar_soltar_reset

fim_verifica_botoes:
    ret


; --- Função: Inverter flag do cronômetro e avisar "[MODO 2] START" ---
aciona_start:
    lds temp1, mode_2+2
    ldi temp2, 1
    eor temp1, temp2
    sts mode_2+2, temp1

    rcall beep_modo

    ldi ZL, low(str_modo2_run<<1)
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String

    ret


; --- Função: Resetar cronômetro (se parado) e avisar "[MODO 2] RESET" ---
aciona_reset:
    lds temp1, mode_2+2
    cpi temp1, 0
    brne reset_nop

    ldi temp1, 0
    sts mode_2, temp1
    sts mode_2+1, temp1

    rcall beep_modo

    ldi ZL, low(str_modo2_stop<<1)
    ldi ZH, high(str_modo2_stop<<1)
    rcall USART_Transmit_String
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String

reset_nop:
    ret


; --- INTERRUPÇÃO PCINT0 ---
pcint0_isr:
    push temp1

    ; Detecta botão pressionado
    in temp1, PINB
    sbrs temp1, PB5
    rjmp seta_flag_troca_modo

    rjmp fim_interrupcao_pcint0

seta_flag_troca_modo:
    ldi temp1, 1
    sts trocar_modo_flag, temp1  ; Marca a flag
fim_interrupcao_pcint0:
    pop temp1
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
    ; --- Atualiza relógio e cronômetro SEMPRE ---
    rcall hora_atual
    rcall cronometro

    ; --- Envia pela UART APENAS conforme o modo atual ---
    cpi actual_mode, 1
    breq send_mode1
    cpi actual_mode, 2
    breq send_mode2
    cpi actual_mode, 3
    brne continuar_uart
    rjmp send_mode3

    continuar_uart:
        rjmp isr_end

    rjmp isr_end

send_mode1:
    ldi ZL, low(str_modo1<<1)
    ldi ZH, high(str_modo1<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_1
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_1+1
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

send_mode2:
    lds temp1, mode_2+2
    cpi temp1, 0
    breq check_mode2_zero
    ldi ZL, low(str_modo2_run<<1)
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2+1
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit


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
multiplexar_display:
    ; Seleciona os dados corretos conforme o modo
    cpi actual_mode, 2
    breq usa_dados_cronometro

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

