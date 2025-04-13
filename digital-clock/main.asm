.include "m328pdef.inc"          ; Inclui definições específicas do ATmega328P

; ============================================================
; DEFINIÇÕES DE CONSTANTES E MACROS
; ============================================================
#define CLOCK 16000000            ; Velocidade do clock = 16 MHz
#define DELAY 1                   ; Constante de delay (usada no Timer) -> 1 segundo
#define BAUD 9600                 ; Taxa de transmissão da serial = 9600 baud
#define UBRR_VALUE (((CLOCK / (BAUD * 16.0)) + 0.5) - 1) ; Cálculo do valor UBRR para configuração do USART

; ============================================================
; DEFINIÇÃO DE REGISTRADORES DE TRABALHO (DEF)
; ============================================================
.def actual_mode = r18        ; r18: Armazena o modo atual de operação (1=Relógio, 2=Cronômetro, 3=Ajuste)
.def temp1 = r16              ; r16: Variável temporária (uso geral)
.def temp2 = r17              ; r17: Variável temporária (uso geral)
.def tx_byte = r19            ; r19: Byte que será transmitido pela serial
.def byte_val = r20           ; r20: Byte a ser convertido para formato ASCII decimal
.def ascii_H = r21            ; r21: Dígito ASCII referente à dezena
.def ascii_L = r22            ; r22: Dígito ASCII referente à unidade
; R23, R24, R25, R26: Usados para armazenar dígitos para o display
; Registrador Z (r31:r30): Ponteiro para strings na memória de programa

; ============================================================
; DEFINIÇÃO DE VARIÁVEIS NA MEMÓRIA DE DADOS (DSEG)
; ============================================================
.dseg
mode_1: .byte 2              ; Reserva 2 bytes: [0]=Minutos, [1]=Segundos (Relógio)
mode_2: .byte 3              ; Reserva 3 bytes: [0]=Minutos, [1]=Segundos, [2]=Flag Ativo (Cronômetro)
adjust_digit_selector: .byte 1 ; Reserva 1 byte para o dígito a ajustar no modo 3:
                              ; (0=Seg Unidade, 1=Seg Dezena, 2=Min Unidade, 3=Min Dezena)
trocar_modo_flag: .byte 1      ; Flag para indicar a troca de modo

; ============================================================
; INÍCIO DO CÓDIGO (CSEG)
; ============================================================
.cseg

; ------------------------------------------------------------
; Vetores de Interrupção
; ------------------------------------------------------------
.org 0x0000
    jmp reset                ; Vetor de reset

.org PCI0addr
    jmp pcint0_isr           ; Vetor da interrupção PCINT0 (Botão MODE - PB5)

.org OC1Aaddr
    jmp OCI1A_ISR            ; Vetor da interrupção Timer1 Compare A (1 segundo)

; ------------------------------------------------------------
; Strings para a comunicação Serial (memória de programa)
; ------------------------------------------------------------
str_modo1: .db "[MODO 1] ", 0
str_modo2_run: .db "[MODO 2] START", 0 ; Alterado para corresponder ao requisito
str_modo2_stop: .db "[MODO 2] STOPPED ", 0 ; Mantido para clareza, mas não pedido explicitamente
str_modo2_zero: .db "[MODO 2] ZERO", 0
str_modo3_su: .db "[MODO 3] Ajustando a unidade dos segundos", 0
str_modo3_sd: .db "[MODO 3] Ajustando a dezena dos segundos ", 0
str_modo3_mu: .db "[MODO 3] Ajustando a unidade dos minutos ", 0
str_modo3_md: .db "[MODO 3] Ajustando a dezena dos minutos", 0
str_modo2_reset: .db "[MODO 2] RESET", 0 ; ;; --- NOVO --- String para Reset no modo 2
str_colon: .db ":", 0
str_newline: .db "\r\n", 0   ; Removido espaço extra

; ============================================================
; ROTINA DE RESET (Inicialização)
; ============================================================
reset:
    ; --- Inicialização da Pilha ---
    ldi r16, low(RAMEND)
    out SPL, r16
    ldi r16, high(RAMEND)
    out SPH, r16

    ; --- Configuração PORTB ---
    ; PB0-3 Saída (Seletores Display), PB4 Saída (Buzzer), PB5 Entrada (Botão MODE c/ Pull-up)
    ldi r16, (1<<DDB4)|(1<<DDB3)|(1<<DDB2)|(1<<DDB1)|(1<<DDB0) ; PB0-4 como saída
    out DDRB, r16
    ldi r16, (1<<PORTB5) ; Ativa Pull-up em PB5
    out PORTB, r16

    ; --- Configuração PORTD ---
    ; PD2-5 Saída (Dados CD4511), PD6 Entrada (RESET c/ Pull-up), PD7 Entrada (START c/ Pull-up)
    ldi r16, (1<<DDD5)|(1<<DDD4)|(1<<DDD3)|(1<<DDD2) ; PD2-5 como saída
    out DDRD, r16
    ldi r16, (1<<PORTD7)|(1<<PORTD6) ; Ativa Pull-up em PD6 e PD7
    out PORTD, r16

    ; --- Interrupção PCINT0 (para PB5 - MODE) ---
    ldi r16, (1 << PCIE0)   ; Habilita PCINT0-7 (PORTB)
    sts PCICR, r16
    ldi r16, (1 << PCINT5)  ; Habilita máscara para PCINT5 (PB5)
    sts PCMSK0, r16

    ; --- Inicialização das Variáveis ---
    ldi temp1, 0
    sts mode_1, temp1         ; Zera Minutos Relógio
    sts mode_1 + 1, temp1     ; Zera Segundos Relógio
    sts mode_2, temp1         ; Zera Minutos Cronômetro
    sts mode_2 + 1, temp1     ; Zera Segundos Cronômetro
    sts mode_2 + 2, temp1     ; Zera Flag Cronômetro (Parado)
    sts adjust_digit_selector, temp1 ; Zera Seletor de Ajuste
    sts trocar_modo_flag, temp1 ; Zera Flag Troca Modo

    ; --- Configuração do Timer1 (CTC, Prescaler 256, Interrupção a cada 1 segundo) ---
    ldi temp1, (1 << OCIE1A)  ; Habilita interrupção Compare A
    sts TIMSK1, temp1
    .equ PRESCALE = 0b100     ; CS12=1, CS11=0, CS10=0 => Prescaler 256
    .equ PRESCALE_DIV = 256
    .equ WGM = 0b0100         ; Modo CTC (OCR1A como TOP)
    ; TOP = Clock / Prescaler * Delay_Segundos = 16MHz / 256 * 1 = 62500
    .equ TOP = 62500

    ldi temp1, high(TOP-1)    ; OCR1A = TOP - 1
    sts OCR1AH, temp1
    ldi temp1, low(TOP-1)
    sts OCR1AL, temp1
    ldi temp1, ((WGM & 0b11) << WGM10) ; Configura WGM11:10 em TCCR1A
    sts TCCR1A, temp1
    ldi temp1, (((WGM >> 2) & 0b11) << WGM12) | (PRESCALE << CS10) ; Configura WGM13:12 e Prescaler em TCCR1B
    sts TCCR1B, temp1

    ; --- Configuração do USART (Serial) ---
    ldi temp1, high(int(UBRR_VALUE))
    sts UBRR0H, temp1
    ldi temp1, low(int(UBRR_VALUE))
    sts UBRR0L, temp1
    ldi temp1, (1 << TXEN0)   ; Habilita transmissor
    sts UCSR0B, temp1
    ldi temp1, (1 << UCSZ01) | (1 << UCSZ00) ; Frame: 8 data bits, 1 stop bit
    sts UCSR0C, temp1

    ; --- Estado Inicial e Habilitação Global de Interrupções ---
    ldi actual_mode, 1       ; Começa no Modo 1
    sei                      ; Habilita interrupções

; ============================================================
; LOOP PRINCIPAL
; ============================================================
main:
    ; Verifica se a flag de troca de modo foi acionada pela interrupção PCINT0
    lds temp1, trocar_modo_flag
    cpi temp1, 1
    brne verificar_botoes ; Se não, verifica outros botões

    ; Se a flag está acionada, troca o modo e faz o beep
    rcall beep_modo       ; Beep para indicar a troca
    rcall trocar_modo     ; Executa a lógica de troca de modo

; ============================
; CONTROLE DE MODO E VERIFICAÇÃO DE BOTÕES
; ============================
verificar_botoes:
    ; Verifica em qual modo estamos para chamar a rotina de botões correta
    cpi actual_mode, 2
    breq chamar_verif_modo2 ; Se MODO 2, verifica START/RESET do cronômetro
    cpi actual_mode, 3
    breq chamar_verif_modo3 ; ;; --- ALTERADO --- Se MODO 3, verifica START/RESET do ajuste
    rjmp continuar_loop     ; Se MODO 1 (ou outro), não há botões START/RESET ativos

chamar_verif_modo2:
    rcall verifica_botoes_modo2
    rjmp continuar_loop

;; --- NOVO --- Bloco para chamar verificação do Modo 3
chamar_verif_modo3:
    rcall verifica_botoes_modo3
    rjmp continuar_loop

continuar_loop:
    ; Multiplexação para atualizar os displays de 7 segmentos
    rcall multiplexar_display
    rjmp main             ; Volta para o início do loop

; ============================================================
; FUNÇÃO: beep_modo
; Finalidade: Emite um beep curto usando PB4.
; ============================================================
beep_modo:
    sbi PORTB, PB4          ; Liga Buzzer (PB4)
    rcall delay_50ms        ; ;; --- NOVO --- Pequeno delay para o beep
    cbi PORTB, PB4          ; Desliga Buzzer
    ret

; ;; --- NOVO --- Função de Delay (aproximado)
delay_50ms:
    push r24
    push r25
    ldi r25, high(16000) ; ~50ms delay loop count (ajustar se necessário)
    ldi r24, low(16000)
delay_50ms_loop:
    sbiw r24, 1
    brne delay_50ms_loop
    pop r25
    pop r24
    ret

; ============================================================
; FUNÇÃO: trocar_modo
; Finalidade: Troca o modo de operação (1 -> 2 -> 3 -> 1) e inicializa estados.
; ============================================================
trocar_modo:
    mov temp1, actual_mode
    inc temp1               ; Próximo modo
    cpi temp1, 4            ; Chegou ao fim (depois do 3)?
    brlo modo_ok
    ldi temp1, 1            ; Volta para o modo 1
modo_ok:
    mov actual_mode, temp1  ; Atualiza o modo

    ldi temp2, 0            ; Zera o registrador temporário
    sts trocar_modo_flag, temp2 ; Limpa a flag de troca de modo

    ; ;; --- ALTERADO --- Inicializações específicas ao entrar em um modo
    cpi actual_mode, 2      ; Entrando no modo 2?
    brne check_enter_mode3
    ; Zera display do cronômetro (valores de mode_2 já são zerados no reset,
    ; mas pode ser bom zerar aqui também se necessário)
    sts mode_2, temp2        ; Zera minutos cronômetro
    sts mode_2 + 1, temp2    ; Zera segundos cronômetro
    sts mode_2 + 2, temp2    ; Garante que cronômetro começa parado
    rjmp trocar_modo_end

check_enter_mode3:
    cpi actual_mode, 3      ; Entrando no modo 3?
    brne trocar_modo_end
    sts adjust_digit_selector, temp2 ; ;; --- NOVO --- Zera o seletor de dígito ao entrar no modo 3

trocar_modo_end:
    ret

; ============================================================
; FUNÇÃO: verifica_botoes_modo2
; Finalidade: Verifica botões START (PD7) e RESET (PD6) no Modo 2 (Cronômetro).
; ============================================================
verifica_botoes_modo2:
    ; Debounce simples por espera após detecção
    rcall delay_50ms ; Pequeno delay para debounce inicial

    ; Verifica START (PD7) - Ativo em nível baixo (pressionado)
    sbic PIND, PD7          ; Pula se PD7 estiver ALTO (não pressionado)
    rjmp verifica_reset_modo2 ; Se não pressionado, verifica RESET
    ; START está pressionado
    rcall aciona_start_modo2 ; Chama a ação do START
    ; Espera o botão ser solto
esperar_soltar_start_m2:
    sbis PIND, PD7          ; Pula se PD7 estiver BAIXO (ainda pressionado)
    rjmp esperar_soltar_start_m2 ; Continua esperando
    rcall delay_50ms ; Delay após soltar para debounce
    rjmp fim_verificacao_botoes_m2 ; Já tratou um botão, sai

verifica_reset_modo2:
    ; Verifica RESET (PD6) - Ativo em nível baixo
    sbic PIND, PD6          ; Pula se PD6 estiver ALTO (não pressionado)
    rjmp fim_verificacao_botoes_m2 ; Se não pressionado, termina
    ; RESET está pressionado
    rcall aciona_reset_modo2 ; Chama a ação do RESET
    ; Espera o botão ser solto
esperar_soltar_reset_m2:
    sbis PIND, PD6          ; Pula se PD6 estiver BAIXO (ainda pressionado)
    rjmp esperar_soltar_reset_m2 ; Continua esperando
    rcall delay_50ms ; Delay após soltar

fim_verificacao_botoes_m2:
    ret

; ============================================================
; FUNÇÃO: aciona_start_modo2
; Finalidade: Inicia/Para o cronômetro (Modo 2), faz beep e envia msg serial.
; ============================================================
aciona_start_modo2:
    lds temp1, mode_2+2      ; Lê flag de ativação
    ldi temp2, 1
    eor temp1, temp2         ; Inverte a flag (0->1 ou 1->0)
    sts mode_2+2, temp1      ; Salva nova flag
    rcall beep_modo          ; Beep

    ; Envia "[MODO 2] START" via serial (Requisito)
    ldi ZL, low(str_modo2_run<<1)
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String
    ret

; ============================================================
; FUNÇÃO: aciona_reset_modo2
; Finalidade: Zera o cronômetro (Modo 2) se estiver parado, faz beep e envia msg serial.
; ============================================================
aciona_reset_modo2:
    lds temp1, mode_2+2      ; Lê flag de ativação
    cpi temp1, 0             ; Está parado (flag == 0)?
    brne reset_m2_nop        ; Se não estiver parado, não faz nada
    ; Se está parado, zera os valores
    ldi temp1, 0
    sts mode_2, temp1        ; Zera minutos
    sts mode_2+1, temp1      ; Zera segundos
    rcall beep_modo          ; Beep

    ; Envia "[MODO 2] RESET" via serial (Requisito)
    ldi ZL, low(str_modo2_reset<<1)
    ldi ZH, high(str_modo2_reset<<1)
    rcall USART_Transmit_String
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String
reset_m2_nop:
    ret

; ============================================================
; ;; --- NOVO --- FUNÇÕES PARA O MODO 3
; ============================================================

; ============================================================
; FUNÇÃO: verifica_botoes_modo3
; Finalidade: Verifica botões START (PD7) e RESET (PD6) no Modo 3 (Ajuste).
; ============================================================
verifica_botoes_modo3:
    ; Debounce simples por espera após detecção
    rcall delay_50ms

    ; Verifica START (PD7) - Seleciona próximo dígito
    sbic PIND, PD7
    rjmp verifica_reset_modo3
    ; START pressionado
    rcall aciona_start_modo3
esperar_soltar_start_m3:
    sbis PIND, PD7
    rjmp esperar_soltar_start_m3
    rcall delay_50ms
    rjmp fim_verificacao_botoes_m3

verifica_reset_modo3:
    ; Verifica RESET (PD6) - Incrementa dígito selecionado
    sbic PIND, PD6
    rjmp fim_verificacao_botoes_m3
    ; RESET pressionado
    rcall aciona_reset_modo3
esperar_soltar_reset_m3:
    sbis PIND, PD6
    rjmp esperar_soltar_reset_m3
    rcall delay_50ms

fim_verificacao_botoes_m3:
    ret

; ============================================================
; FUNÇÃO: aciona_start_modo3
; Finalidade: Avança o seletor de dígito (0->1->2->3->0) no Modo 3.
; ============================================================
aciona_start_modo3:
    push temp1
    lds temp1, adjust_digit_selector
    inc temp1
    cpi temp1, 4       ; Chegou a 4? (Após dígito 3)
    brne start_m3_store
    ldi temp1, 0       ; Volta para o dígito 0 (Unidade Segundos)
start_m3_store:
    sts adjust_digit_selector, temp1
    ; Não faz beep aqui para diferenciar do RESET
    pop temp1
    ret

; ============================================================
; FUNÇÃO: aciona_reset_modo3
; Finalidade: Incrementa o dígito selecionado do relógio (mode_1) no Modo 3.
;             Trata wrap-around (0-9 para unidades, 0-5 para dezenas).
; Usa: r20 (selector), r21 (tens), r22 (units), temp1, temp2
; ============================================================
aciona_reset_modo3:
    push temp1
    push temp2
    push r20
    push r21
    push r22

    ; Carrega o seletor atual
    lds r20, adjust_digit_selector ; r20 = selector (0..3)

    ; Determina se estamos ajustando segundos (0, 1) ou minutos (2, 3)
    cpi r20, 2
    brlo reset_m3_processa_segundos ; Se for 0 ou 1, vai para segundos

; --- Processa Ajuste dos Minutos ---
reset_m3_processa_minutos:
    lds temp1, mode_1       ; Carrega byte dos minutos
    rcall div10             ; Divide por 10 -> temp1=dezena, temp2=unidade
    mov r21, temp1          ; r21 = dezena minutos
    mov r22, temp2          ; r22 = unidade minutos

    ; Verifica se ajusta unidade (2) ou dezena (3)
    cpi r20, 2
    breq reset_m3_inc_unidade_min

reset_m3_inc_dezena_min: ; Ajustando dezena dos minutos (selector = 3)
    inc r21                 ; Incrementa dezena
    cpi r21, 6              ; Dezena de minutos vai de 0 a 5
    brlo reset_m3_recombina_min ; Se < 6, ok
    ldi r21, 0              ; Se 6, volta para 0
    rjmp reset_m3_recombina_min

reset_m3_inc_unidade_min: ; Ajustando unidade dos minutos (selector = 2)
    inc r22                 ; Incrementa unidade
    cpi r22, 10             ; Unidade vai de 0 a 9
    brlo reset_m3_recombina_min ; Se < 10, ok
    ldi r22, 0              ; Se 10, volta para 0

reset_m3_recombina_min:
    ; Recombina dezena e unidade: valor = dezena * 10 + unidade
    mov temp1, r21          ; temp1 = dezena
    rcall mult10            ; temp1 = dezena * 10 (usa temp2 internamente)
    add temp1, r22          ; temp1 = dezena * 10 + unidade
    sts mode_1, temp1       ; Salva o novo valor dos minutos
    rjmp reset_m3_fim

; --- Processa Ajuste dos Segundos ---
reset_m3_processa_segundos:
    lds temp1, mode_1+1     ; Carrega byte dos segundos
    rcall div10             ; Divide por 10 -> temp1=dezena, temp2=unidade
    mov r21, temp1          ; r21 = dezena segundos
    mov r22, temp2          ; r22 = unidade segundos

    ; Verifica se ajusta unidade (0) ou dezena (1)
    cpi r20, 0
    breq reset_m3_inc_unidade_sec

reset_m3_inc_dezena_sec: ; Ajustando dezena dos segundos (selector = 1)
    inc r21                 ; Incrementa dezena
    cpi r21, 6              ; Dezena de segundos vai de 0 a 5
    brlo reset_m3_recombina_sec
    ldi r21, 0              ; Se 6, volta para 0
    rjmp reset_m3_recombina_sec

reset_m3_inc_unidade_sec: ; Ajustando unidade dos segundos (selector = 0)
    inc r22                 ; Incrementa unidade
    cpi r22, 10             ; Unidade vai de 0 a 9
    brlo reset_m3_recombina_sec
    ldi r22, 0              ; Se 10, volta para 0

reset_m3_recombina_sec:
    ; Recombina dezena e unidade: valor = dezena * 10 + unidade
    mov temp1, r21          ; temp1 = dezena
    rcall mult10            ; temp1 = dezena * 10
    add temp1, r22          ; temp1 = dezena * 10 + unidade
    sts mode_1+1, temp1     ; Salva o novo valor dos segundos

reset_m3_fim:
    rcall beep_modo         ; Beep para indicar que o ajuste foi feito
    pop r22
    pop r21
    pop r20
    pop temp2
    pop temp1
    ret

; ============================================================
; INTERRUPÇÃO PCINT0 (Botão MODE - PB5)
; ============================================================
pcint0_isr:
    ; Debounce muito simples: apenas checa se está baixo
    push temp1
    in temp1, SREG          ; Salva SREG
    push temp1

    in temp1, PINB
    sbrc temp1, PB5         ; Pula se PB5 estiver ALTO (não pressionado)
    rjmp seta_flag_troca_modo ; Se BAIXO (pressionado), seta a flag

fim_interrupcao_pcint0:
    pop temp1
    out SREG, temp1         ; Restaura SREG
    pop temp1
    reti

seta_flag_troca_modo:
    ; Verifica se a flag já está setada para evitar múltiplas trocas rápidas
    lds temp1, trocar_modo_flag
    cpi temp1, 1
    breq fim_interrupcao_pcint0 ; Se já está 1, não faz nada

    ldi temp1, 1            ; Seta a flag para 1
    sts trocar_modo_flag, temp1
    rjmp fim_interrupcao_pcint0 ; Vai para o fim (não precisa pular de novo)

; ============================================================
; INTERRUPÇÃO DO TIMER 1 (OCI1A_ISR - 1 Segundo)
; ============================================================
OCI1A_ISR:
    ; --- Salvar Contexto ---
    push temp1
    push temp2
    push r19 ; tx_byte
    push r20 ; byte_val
    push r21 ; ascii_H
    push r22 ; ascii_L
    push r30 ; ZL
    push r31 ; ZH
    in temp1, SREG
    push temp1

    ; --- Atualiza Relógio e Cronômetro ---
    rcall hora_atual        ; Atualiza mode_1 (sempre)
    rcall cronometro        ; Atualiza mode_2 (se ativo)

    ; --- Envia dados pela USART conforme o modo atual ---
    cpi actual_mode, 1
    breq send_mode1
    cpi actual_mode, 2
    breq send_mode2
    cpi actual_mode, 3
    breq send_mode3      ; ;; --- ALTERADO --- Vai direto para send_mode3 se for modo 3
    rjmp isr_end           ; Se não for 1, 2 ou 3 (não deve acontecer), apenas sai

; --- Envio Serial no Modo 1 ---
send_mode1:
    ldi ZL, low(str_modo1<<1)
    ldi ZH, high(str_modo1<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_1     ; Minutos
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_1+1    ; Segundos
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

; --- Envio Serial no Modo 2 ---
send_mode2:
    lds temp1, mode_2+2      ; Flag ativo?
    cpi temp1, 0
    breq check_mode2_zero    ; Se parado, verifica se é zero
    ; Se rodando:
    ldi ZL, low(str_modo2_run<<1) ; Mensagem "START"
    ldi ZH, high(str_modo2_run<<1)
    rcall USART_Transmit_String
    ; Adiciona o tempo atual do cronômetro após "START"
    lds byte_val, mode_2     ; Minutos
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2+1   ; Segundos
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

check_mode2_zero:
    lds temp1, mode_2        ; Minutos
    lds temp2, mode_2+1      ; Segundos
    or temp1, temp2          ; Se ambos 0, resultado é 0
    brne mode2_stopped       ; Se não for zero, está parado mas não zerado
    ; Se ambos zero:
    ldi ZL, low(str_modo2_zero<<1) ; Mensagem "ZERO"
    ldi ZH, high(str_modo2_zero<<1)
    rcall USART_Transmit_String
    rjmp send_newline_and_exit

mode2_stopped:
    ; Parado e não zerado (Opcional, não explicitamente pedido, mas útil)
    ldi ZL, low(str_modo2_stop<<1) ; Mensagem "STOPPED"
    ldi ZH, high(str_modo2_stop<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2      ; Minutos
    rcall Send_Decimal_Byte
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String
    lds byte_val, mode_2+1    ; Segundos
    rcall Send_Decimal_Byte
    rjmp send_newline_and_exit

; --- Envio Serial no Modo 3 ---
send_mode3:
    lds temp1, adjust_digit_selector ; Carrega qual dígito está sendo ajustado
    cpi temp1, 0
    breq send_m3_su
    cpi temp1, 1
    breq send_m3_sd
    cpi temp1, 2
    breq send_m3_mu
    cpi temp1, 3
    breq send_m3_md
    rjmp send_newline_and_exit ; Caso inválido

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
    ; Cai direto para send_newline_and_exit

send_newline_and_exit:
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String

isr_end:
    ; --- Restaurar Contexto ---
    pop temp1
    out SREG, temp1
    pop r31 ; ZH
    pop r30 ; ZL
    pop r22 ; ascii_L
    pop r21 ; ascii_H
    pop r20 ; byte_val
    pop r19 ; tx_byte
    pop temp2
    pop temp1
    reti

; ============================================================
; FUNÇÃO: hora_atual
; Finalidade: Atualiza relógio (mode_1) a cada segundo.
; ============================================================
hora_atual:
    push temp1
    push temp2
    lds temp2, mode_1 + 1   ; Segundos atuais
    inc temp2
    cpi temp2, 60
    brne save_seconds
; Atualiza minuto se segundos == 60
    lds temp1, mode_1       ; Minutos atuais
    inc temp1
    cpi temp1, 60
    brne save_minutes
    ldi temp1, 0           ; Zera minutos se == 60
save_minutes:
    sts mode_1, temp1      ; Salva minutos
    ldi temp2, 0           ; Zera segundos
save_seconds:
    sts mode_1 + 1, temp2  ; Salva segundos
    pop temp2
    pop temp1
    ret

; ============================================================
; FUNÇÃO: cronometro
; Finalidade: Atualiza cronômetro (mode_2) se estiver ativo.
; ============================================================
cronometro:
    push temp1
    push temp2
    lds temp1, mode_2 + 2   ; Flag ativo?
    cpi temp1, 0
    breq crono_end         ; Se não ativo, sai
; Se ativo:
    lds temp2, mode_2 + 1   ; Segundos cronômetro
    inc temp2
    cpi temp2, 60
    brne crono_save_seconds
; Atualiza minuto cronômetro se segundos == 60
    lds temp1, mode_2       ; Minutos cronômetro
    inc temp1
    cpi temp1, 60
    brne crono_save_minutes
    ldi temp1, 0           ; Zera minutos se == 60
crono_save_minutes:
    sts mode_2, temp1      ; Salva minutos cronômetro
    ldi temp2, 0           ; Zera segundos cronômetro
crono_save_seconds:
    sts mode_2 + 1, temp2  ; Salva segundos cronômetro
crono_end:
    pop temp2
    pop temp1
    ret

; ============================================================
; FUNÇÃO: multiplexar_display
; Finalidade: Atualiza display 7 segmentos com valor do modo atual.
;             Exibe mode_1 nos modos 1 e 3, mode_2 no modo 2.
; Usa: r23(SegU), r24(SegD), r25(MinU), r26(MinD)
; ============================================================
multiplexar_display:
    push temp1
    push temp2
    push r23
    push r24
    push r25
    push r26

    ; Seleciona dados baseado no modo
    cpi actual_mode, 2
    breq usa_dados_cronometro

; --- Usa dados do Relógio (Modo 1 ou 3) ---
usa_dados_relogio:
    lds temp1, mode_1 + 1    ; Segundos (mode_1[1])
    rcall div10              ; temp1=dezena, temp2=unidade
    mov r24, temp1           ; Dezena Segundos -> r24
    mov r23, temp2           ; Unidade Segundos -> r23

    lds temp1, mode_1        ; Minutos (mode_1[0])
    rcall div10
    mov r26, temp1           ; Dezena Minutos -> r26
    mov r25, temp2           ; Unidade Minutos -> r25
    rjmp exibir_valores

; --- Usa dados do Cronômetro (Modo 2) ---
usa_dados_cronometro:
    lds temp1, mode_2 + 1    ; Segundos (mode_2[1])
    rcall div10
    mov r24, temp1           ; Dezena Segundos -> r24
    mov r23, temp2           ; Unidade Segundos -> r23

    lds temp1, mode_2        ; Minutos (mode_2[0])
    rcall div10
    mov r26, temp1           ; Dezena Minutos -> r26
    mov r25, temp2           ; Unidade Minutos -> r25

exibir_valores:
    ; Ativa Dígito Unidade Segundos (PB3)
    mov temp1, r23         ; Valor Unidade Segundos
    rcall enviar_para_cd4511
    sbi PORTB, PB3         ; Ativa seletor do dígito
    rcall delay_multiplex
    cbi PORTB, PB3         ; Desativa seletor

    ; Ativa Dígito Dezena Segundos (PB2)
    mov temp1, r24         ; Valor Dezena Segundos
    rcall enviar_para_cd4511
    sbi PORTB, PB2
    rcall delay_multiplex
    cbi PORTB, PB2

    ; Ativa Dígito Unidade Minutos (PB1)
    mov temp1, r25         ; Valor Unidade Minutos
    rcall enviar_para_cd4511
    sbi PORTB, PB1
    rcall delay_multiplex
    cbi PORTB, PB1

    ; Ativa Dígito Dezena Minutos (PB0)
    mov temp1, r26         ; Valor Dezena Minutos
    rcall enviar_para_cd4511
    sbi PORTB, PB0
    rcall delay_multiplex
    cbi PORTB, PB0

    pop r26
    pop r25
    pop r24
    pop r23
    pop temp2
    pop temp1
    ret

; ============================================================
; FUNÇÃO: enviar_para_cd4511
; Finalidade: Envia valor BCD (em temp1) para PD5, PD4, PD3, PD2.
; ============================================================
enviar_para_cd4511:
    ; Assume que temp1 contém o dígito (0-9)
    ; Mapeamento: PD5=D, PD4=C, PD3=B, PD2=A
    push temp2
    in temp2, PORTD        ; Lê estado atual de PORTD
    andi temp2, 0b11000011 ; Zera bits PD2, PD3, PD4, PD5
    ; Isola bits de temp1 e desloca para posições corretas
    ; Bit 0 (A) -> PD2
    sbrc temp1, 0
    ori temp2, (1<<PD2)
    ; Bit 1 (B) -> PD3
    sbrc temp1, 1
    ori temp2, (1<<PD3)
    ; Bit 2 (C) -> PD4
    sbrc temp1, 2
    ori temp2, (1<<PD4)
    ; Bit 3 (D) -> PD5
    sbrc temp1, 3
    ori temp2, (1<<PD5)
    out PORTD, temp2       ; Escreve valor BCD em PORTD
    pop temp2
    ret

; ============================================================
; FUNÇÃO: dividir (Já existente, renomeada se necessário)
; Finalidade: Divisão inteira temp1 / temp2. Retorna: temp1=quociente, temp2=resto.
;             A subrotina div10 é mais específica e talvez mais eficiente aqui.
; ============================================================
; Se precisar da função 'dividir' genérica, inclua-a aqui.
; Caso contrário, confie na 'div10' que já existe.

; ============================================================
; FUNÇÃO: delay_multiplex
; Finalidade: Pequeno delay para a multiplexação do display (~5ms).
; ============================================================
delay_multiplex:
    push r24
    push r25
    ldi r25, high(1000) ; Ajuste este valor para o tempo desejado (~5ms)
    ldi r24, low(1000)
delay_mux_loop:
    sbiw r24, 1
    brne delay_mux_loop
    pop r25
    pop r24
    ret

; ============================================================
; FUNÇÕES DE TRANSMISSÃO SERIAL (USART) - Sem alterações
; ============================================================
USART_Transmit:
    push temp1
tx_wait_loop:
    lds temp1, UCSR0A
    sbrs temp1, UDRE0
    rjmp tx_wait_loop
    sts UDR0, tx_byte
    pop temp1
    ret

USART_Transmit_String:
    push temp1
    push r30
    push r31
str_loop:
    lpm tx_byte, Z+
    tst tx_byte
    breq str_end
    rcall USART_Transmit
    rjmp str_loop
str_end:
    pop r31
    pop r30
    pop temp1
    ret

Send_Decimal_Byte:
    push temp1
    push temp2 ; Salva temp2 também, pois div10 o modifica
    push r20   ; Salva byte_val
    mov temp1, byte_val
    rcall div10 ; temp1=dezena, temp2=resto(unidade)
    mov ascii_H, temp1 ; Dezena
    mov ascii_L, temp2 ; Unidade

    subi ascii_H, -'0' ; Converte dezena para ASCII
    mov tx_byte, ascii_H
    rcall USART_Transmit
    subi ascii_L, -'0' ; Converte unidade para ASCII
    mov tx_byte, ascii_L
    rcall USART_Transmit
    pop r20
    pop temp2 ; Restaura temp2
    pop temp1
    ret

; ============================================================
; FUNÇÃO: div10
; Finalidade: Divide temp1 por 10. Saída: temp1=resto, temp2=quociente.
;             (Nota: A implementação original retornava quociente em temp1 e resto em temp2.
;              Ajustei para corresponder ao uso em Send_Decimal_Byte e aciona_reset_modo3)
; ============================================================
div10:
    clr temp2              ; Zera quociente (temp2)
div10_loop:
    cpi temp1, 10          ; Compara dividendo (temp1) com 10
    brlo div10_end         ; Se < 10, temp1 é o resto, fim.
    subi temp1, 10         ; Subtrai 10 do dividendo
    inc temp2              ; Incrementa quociente
    rjmp div10_loop        ; Repete
div10_end:
    ; No final: temp1 = resto, temp2 = quociente
    ; Troca para retornar como esperado pelas rotinas que chamam:
    push temp1             ; Salva resto
    mov temp1, temp2       ; temp1 = quociente
    pop temp2              ; temp2 = resto
    ret

; ============================================================
; ;; --- NOVO --- FUNÇÃO: mult10
; Finalidade: Multiplica temp1 por 10.
; Entrada: temp1
; Saída: temp1 = temp1 * 10
; Usa: temp2 (como temporário)
; ============================================================
mult10:
    mov temp2, temp1   ; temp2 = x
    lsl temp1          ; temp1 = x * 2
    lsl temp1          ; temp1 = x * 4
    add temp1, temp2   ; temp1 = x * 4 + x = x * 5
    lsl temp1          ; temp1 = x * 5 * 2 = x * 10
    ret