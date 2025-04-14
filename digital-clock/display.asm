; =========================================================================
; FUN��ES DE DISPLAY
; =========================================================================
multiplexar_display:
    ; Seleciona os dados corretos conforme o modo
    cpi actual_mode, 2
    breq usa_dados_cronometro
	cpi actual_mode, 3
	brne usa_dados_relogio
	rjmp multiplexar_display_modo3

usa_dados_relogio:
    ; ================================
    ; Separa os dígitos dos SEGUNDOS
    ; ================================

    lds temp1, mode_1 + 1        ; Carrega os segundos do relógio em temp1
    ldi temp2, 10                ; Carrega o número 10 em temp2 (divisor)
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r23, temp2               ; Armazena a unidade dos segundos em r23 (segundos unidade)
    mov r24, temp1               ; Armazena a dezena dos segundos em r24 (segundos dezena)

    ; ================================
    ; Separa os dígitos dos MINUTOS
    ; ================================

    lds temp1, mode_1            ; Carrega os minutos do relógio em temp1
    ldi temp2, 10                ; Carrega o número 10 novamente em temp2
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r25, temp2               ; Armazena a unidade dos minutos em r25 (minutos unidade)
    mov r26, temp1               ; Armazena a dezena dos minutos em r26 (minutos dezena)

    ; Agora temos os quatro dígitos separados em:
    ; r26 = Min Dez, r25 = Min Unid, r24 = Sec Dez, r23 = Sec Unid

    rjmp exibir_valores          ; Pula para a rotina de exibição no display


usa_dados_cronometro:
    ; ====================================
    ; Separa os dígitos dos SEGUNDOS
    ; do cronômetro (armazenado em mode_2+1)
    ; ====================================

    lds temp1, mode_2 + 1        ; Carrega os segundos do cronômetro em temp1
    ldi temp2, 10                ; Carrega o número 10 (divisor) em temp2
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r23, temp2               ; r23 ← unidade dos segundos
    mov r24, temp1               ; r24 ← dezena dos segundos

    ; ====================================
    ; Separa os dígitos dos MINUTOS
    ; do cronômetro (armazenado em mode_2)
    ; ====================================

    lds temp1, mode_2            ; Carrega os minutos do cronômetro em temp1
    ldi temp2, 10                ; Carrega o número 10 (divisor) novamente
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r25, temp2               ; r25 ← unidade dos minutos
    mov r26, temp1               ; r26 ← dezena dos minutos

    ; Resultado final:
    ; r23 = Sec Unid
    ; r24 = Sec Dez
    ; r25 = Min Unid
    ; r26 = Min Dez

    ; Esses valores serão usados em seguida na rotina de exibição para
    ; mostrar os dígitos do cronômetro no display multiplexado.

exibir_valores:
    ; ---------------------------------------------
    ; Exibe o dígito das UNIDADES dos SEGUNDOS (r23)
    ; ---------------------------------------------
    mov temp1, r23                  ; Coloca a unidade dos segundos em temp1
    rcall enviar_para_cd4511        ; Envia o valor em temp1 (0–9) para o CD4511 via PD2–PD5

    in temp2, PORTB                 ; Lê o estado atual de PORTB
    andi temp2, 0b11110000          ; Limpa os bits PB0–PB3 (desliga todos os displays)
    ori temp2, (1 << PB3)           ; Ativa PB3 (seleciona o display da unidade dos segundos)
    out PORTB, temp2                ; Atualiza PORTB para acionar esse display

    rcall delay_multiplex           ; Aguarda um tempo curto para manter o dígito visível

    ; ---------------------------------------------
    ; Exibe o dígito das DEZENAS dos SEGUNDOS (r24)
    ; ---------------------------------------------
    mov temp1, r24                  ; Coloca a dezena dos segundos em temp1
    rcall enviar_para_cd4511        ; Envia para o CD4511

    in temp2, PORTB
    andi temp2, 0b11110000          ; Limpa os bits PB0–PB3
    ori temp2, (1 << PB2)           ; Ativa PB2 (seleciona o display da dezena dos segundos)
    out PORTB, temp2

    rcall delay_multiplex           ; Aguarda para manter o dígito visível

    ; ---------------------------------------------
    ; Exibe o dígito das UNIDADES dos MINUTOS (r25)
    ; ---------------------------------------------
    mov temp1, r25                  ; Coloca a unidade dos minutos em temp1
    rcall enviar_para_cd4511        ; Envia para o CD4511

    in temp2, PORTB
    andi temp2, 0b11110000          ; Limpa os bits PB0–PB3
    ori temp2, (1 << PB1)           ; Ativa PB1 (seleciona o display da unidade dos minutos)
    out PORTB, temp2

    rcall delay_multiplex           ; Aguarda para manter o dígito visível

    ; ---------------------------------------------
    ; Exibe o dígito das DEZENAS dos MINUTOS (r26)
    ; ---------------------------------------------
    mov temp1, r26                  ; Coloca a dezena dos minutos em temp1
    rcall enviar_para_cd4511        ; Envia para o CD4511

    in temp2, PORTB
    andi temp2, 0b11110000          ; Limpa os bits PB0–PB3
    ori temp2, (1 << PB0)           ; Ativa PB0 (seleciona o display da dezena dos minutos)
    out PORTB, temp2

    rcall delay_multiplex           ; Aguarda para manter o dígito visível

    ret                             ; Retorna da sub-rotina


enviar_para_cd4511:
    lsl temp1              ; Desloca os bits de temp1 1 vez para a esquerda (multiplica por 2)
    lsl temp1              ; Desloca novamente (multiplica por 4), alinhando para PD2–PD5
    in temp2, PORTD        ; Lê o valor atual da PORTD para preservar os bits não usados pelo CD4511
    andi temp2, 0b11000011 ; Zera os bits PD2 a PD5 (onde o BCD será inserido), mantendo os outros
    or temp2, temp1        ; Combina os bits BCD deslocados com o restante dos bits preservados
    out PORTD, temp2       ; Atualiza o PORTD com o novo valor, enviando o número para o CD4511
    ret                    ; Retorna da sub-rotina


dividir:
    ; ================================
    ; Inicialização da Divisão
    ; ================================

    push r19            ; Salva o registrador r19 na pilha (será usado como contador do quociente)
    clr r19             ; Zera r19 para começar a contagem do quociente (quantas vezes subtrai o divisor)

div_loop:
    ; ================================
    ; Loop de Subtração Repetida
    ; ================================

    cp temp1, temp2     ; Compara o valor atual (dividendo) com o divisor
    brlo fim_div        ; Se temp1 < temp2, termina a divisão (não dá mais pra subtrair)
    sub temp1, temp2    ; Subtrai o divisor de temp1 (simulando uma divisão)
    inc r19             ; Incrementa o contador de subtrações (quociente)
    rjmp div_loop       ; Repete o processo até temp1 < temp2

fim_div:
    ; ================================
    ; Ajuste dos Resultados
    ; ================================

    mov temp2, temp1    ; O valor que sobrou em temp1 é o resto → vai para temp2 (unidade)
    mov temp1, r19      ; O número de subtrações feitas (em r19) é o quociente → vai para temp1 (dezena)

    pop r19             ; Restaura o valor original de r19 da pilha
    ret                 ; Retorna da sub-rotina com:
                        ; → temp1 = dezena (quociente)
                        ; → temp2 = unidade (resto)


delay_multiplex:
    push r24
    push r25
    ldi r25, high(5000)
    ldi r24, low(5000)
delay_loop:
    sbiw r24, 1
    brne delay_loop
    pop r25
    pop r24
    ret

;-------------------------

multiplexar_display_modo3:
    ; ================================
    ; Separa os dígitos dos SEGUNDOS
    ; ================================

    lds temp1, mode_1 + 1        ; Carrega os segundos do relógio em temp1
    ldi temp2, 10                ; Carrega o número 10 em temp2 (divisor)
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r23, temp2               ; Armazena a unidade dos segundos em r23
    mov r24, temp1               ; Armazena a dezena dos segundos em r24

    ; ================================
    ; Separa os dígitos dos MINUTOS
    ; ================================

    lds temp1, mode_1            ; Carrega os minutos do relógio em temp1
    ldi temp2, 10                ; Carrega o número 10 novamente em temp2
    call dividir                 ; Divide temp1 por 10:
                                 ; → temp1 = dezena (quociente)
                                 ; → temp2 = unidade (resto)
    mov r25, temp2               ; Armazena a unidade dos minutos em r25
    mov r26, temp1               ; Armazena a dezena dos minutos em r26

    ; ================================
    ; Atualiza contador de piscagem
    ; ================================

    lds temp1, blink_counter     ; Carrega o contador de piscagem
    inc temp1                    ; Incrementa o valor (1 a cada chamada da rotina)
    cpi temp1, 150               ; Compara com o limite desejado para alternar visibilidade
                                 ; → Quanto maior o valor, mais devagar o piscar
    brlo salvar_contador         ; Se ainda não atingiu o limite, salva e sai
    ldi temp1, 0                 ; Reseta o contador quando atinge o valor de comparação
          ; Reseta o contador quando atinge o limite

salvar_contador:
    ; ================================
    ; Salva o valor atualizado do contador de piscagem
    ; ================================

    sts blink_counter, temp1    ; Armazena o novo valor de temp1 em blink_counter

    ; ================================
    ; Verifica se o dígito deve ser exibido ou apagado
    ; ================================

    cpi temp1, 10               ; Compara o contador com 10 (meio ciclo do piscar)
    brlo exibe_normal           ; Se for menor que 10 → exibir normalmente

    ; ================================
    ; Se contador >= 10, apaga o dígito selecionado
    ; ================================

    lds temp1, adjust_digit_selector ; Lê qual dígito está sendo ajustado (0 a 3)

    cpi temp1, 0               ; Verifica se é a unidade dos segundos
    brne testa_sd              ; Se não for, pula para o próximo teste

    ldi r23, 10                ; Coloca valor "10" para apagar o dígito da unidade dos segundos (r23)
    rjmp exibe_normal          ; Pula para exibir os demais normalmente, exceto este

testa_sd:
    ; ================================
    ; Verifica se o dígito ajustado é a dezena dos segundos
    ; ================================

    cpi temp1, 1               ; Compara com 1 (dezena dos segundos)
    brne testa_mu              ; Se não for, pula para o próximo teste

    ldi r24, 10                ; Apaga a dezena dos segundos (r24 recebe 10)
    rjmp exibe_normal          ; Pula para a exibição dos outros dígitos

testa_mu:
    ; ================================
    ; Verifica se o dígito ajustado é a unidade dos minutos
    ; ================================

    cpi temp1, 2               ; Compara com 2 (unidade dos minutos)
    brne testa_md              ; Se não for, pula para o próximo teste

    ldi r25, 10                ; Apaga a unidade dos minutos (r25 recebe 10)
    rjmp exibe_normal          ; Pula para a exibição dos outros dígitos

testa_md:
    ; ================================
    ; Verifica se o dígito ajustado é a dezena dos minutos
    ; ================================

    cpi temp1, 3               ; Compara com 3 (dezena dos minutos)
    brne exibe_normal          ; Se não for nenhum dos 4 valores válidos, segue normalmente

    ldi r26, 10                ; Apaga a dezena dos minutos (r26 recebe 10)


exibe_normal:
    ; ================================
    ; Configura o Timer0 para a próxima alternância de multiplexação
    ; ================================

    ldi temp1, (1 << CS02) | (0 << CS01) | (1 << CS00)  ; Define prescaler como 1024 (CS02 e CS00 ligados)
    out TCCR0B, temp1                                   ; Ativa o Timer0 com esse prescaler (usado para multiplexar displays)

    ; ================================
    ; Exibe o dígito da UNIDADE dos SEGUNDOS
    ; ================================

    mov temp1, r23                ; Carrega a unidade dos segundos em temp1
    cpi temp1, 10                 ; Verifica se o valor é 10 (comando para apagar o dígito)
    breq desliga_display_su       ; Se for 10, pula para rotina que desliga esse dígito

    rcall enviar_para_cd4511      ; Envia o valor BCD para os pinos PD2–PD5 (CD4511)
    in temp2, PORTB               ; Lê o valor atual de PORTB
    andi temp2, 0b11110000        ; Limpa os bits de controle PB0–PB3 (desliga todos os displays)
    ori temp2, (1 << PB3)         ; Ativa PB3 (liga o display da unidade dos segundos)
    out PORTB, temp2              ; Atualiza PORTB com esse valor para acionar o display

    rjmp continua_sd              ; Pula para a próxima etapa (exibição da dezena dos segundos)


desliga_display_su:
    ; ================================
    ; Apaga o display da unidade dos segundos (PB3)
    ; ================================

    in temp2, PORTB               ; Lê o valor atual de PORTB
    andi temp2, 0b11110111        ; Desliga PB3 (zera bit 3 → apaga o display)
    out PORTB, temp2              ; Atualiza PORTB com PB3 desligado

continua_sd:
    ; ================================
    ; Exibe o dígito da DEZENA dos SEGUNDOS
    ; ================================

    rcall delay_multiplex         ; Aguarda um pequeno tempo antes de trocar o dígito

    mov temp1, r24                ; Carrega a dezena dos segundos em temp1
    cpi temp1, 10                 ; Verifica se deve apagar o dígito (valor 10 = ocultar)
    breq desliga_display_sd       ; Se for 10, apaga o display

    rcall enviar_para_cd4511      ; Envia o valor para o CD4511 via PD2–PD5
    in temp2, PORTB               ; Lê PORTB
    andi temp2, 0b11110000        ; Limpa PB0–PB3 (controle dos displays)
    ori temp2, (1 << PB2)         ; Ativa PB2 (liga o display da dezena dos segundos)
    out PORTB, temp2              ; Atualiza PORTB

    rjmp continua_mu              ; Pula para a exibição da unidade dos minutos

desliga_display_sd:
    ; ================================
    ; Apaga o display da dezena dos segundos (PB2)
    ; ================================

    in temp2, PORTB
    andi temp2, 0b11111011        ; Desliga PB2 (zera bit 2)
    out PORTB, temp2

continua_mu:
    ; ================================
    ; Exibe o dígito da UNIDADE dos MINUTOS
    ; ================================

    rcall delay_multiplex

    mov temp1, r25                ; Carrega a unidade dos minutos
    cpi temp1, 10                 ; Verifica se deve apagar (valor 10 = ocultar)
    breq desliga_display_mu

    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB1)         ; Ativa PB1 (liga o display da unidade dos minutos)
    out PORTB, temp2

    rjmp continua_md              ; Pula para a exibição da dezena dos minutos

desliga_display_mu:
    ; ================================
    ; Apaga o display da unidade dos minutos (PB1)
    ; ================================

    in temp2, PORTB
    andi temp2, 0b11111101        ; Desliga PB1 (zera bit 1)
    out PORTB, temp2

continua_md:
    ; ================================
    ; Exibe o dígito da DEZENA dos MINUTOS
    ; ================================

    rcall delay_multiplex

    mov temp1, r26                ; Carrega a dezena dos minutos
    cpi temp1, 10                 ; Verifica se deve apagar (valor 10 = ocultar)
    breq desliga_display_md

    rcall enviar_para_cd4511
    in temp2, PORTB
    andi temp2, 0b11110000
    ori temp2, (1 << PB0)         ; Ativa PB0 (liga o display da dezena dos minutos)
    out PORTB, temp2

    rjmp fim_multiplex_modo3      ; Fim da rotina de exibição (modo 3)

desliga_display_md:
    ; ================================
    ; Apaga o display da dezena dos minutos (PB0)
    ; ================================

    in temp2, PORTB
    andi temp2, 0b11111110        ; Desliga PB0 (zera bit 0)
    out PORTB, temp2

fim_multiplex_modo3:
    ; ================================
    ; Delay final da multiplexação (encerra ciclo)
    ; ================================

    rcall delay_multiplex
    ret                           ; Retorna da sub-rotina
