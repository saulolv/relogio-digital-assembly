; =========================================================================
; FUNÇÕES DE DISPLAY
; =========================================================================
; Rotina principal de multiplexação do display, que seleciona os dados de exibição
; conforme o modo de operação do sistema (relógio, cronômetro ou ajuste – modo 3).
multiplexar_display:
    ; Verifica se o modo atual é 2 (cronômetro)
    cpi actual_mode, 2          ; Compara o modo atual com 2
    breq usa_dados_cronometro   ; Se for igual a 2, desvia para processar os dados do cronômetro
    ; Se não for cronômetro, verifica se é modo 3
    cpi actual_mode, 3          ; Compara o modo atual com 3
    brne usa_dados_relogio       ; Se não for 3, utiliza os dados do relógio
    rjmp multiplexar_display_modo3 ; Se for 3, salta para a rotina específica de exibição do modo 3

; -------------------------------------------------------------------------
; Rotina de separação dos dígitos do relógio (modo 1: relógio)
usa_dados_relogio:
    ; -------------------------------
    ; Separa os dígitos dos SEGUNDOS
    ; -------------------------------
    lds temp1, mode_1 + 1       ; Carrega os segundos atuais do relógio (localizados em mode_1 + 1) para temp1
    ldi temp2, 10               ; Prepara o divisor 10 em temp2 para a divisão
    call dividir                ; Chama a sub-rotina que divide temp1 por temp2
                                ; Após a chamada: temp1 contém o quociente (dezena dos segundos)
                                ;                      temp2 contém o resto (unidade dos segundos)
    mov r23, temp2              ; Armazena a unidade dos segundos em r23
    mov r24, temp1              ; Armazena a dezena dos segundos em r24

    ; -------------------------------
    ; Separa os dígitos dos MINUTOS
    ; -------------------------------
    lds temp1, mode_1           ; Carrega os minutos atuais do relógio (localizados em mode_1) para temp1
    ldi temp2, 10               ; Prepara o divisor 10 novamente em temp2
    call dividir                ; Realiza a divisão para separar os dígitos:
                                ; temp1 = dezena dos minutos e temp2 = unidade dos minutos
    mov r25, temp2              ; Armazena a unidade dos minutos em r25
    mov r26, temp1              ; Armazena a dezena dos minutos em r26

    ; Agora os dígitos estão organizados em:
    ; r26 = Minutos Dezena, r25 = Minutos Unidade,
    ; r24 = Segundos Dezena, r23 = Segundos Unidade
    rjmp exibir_valores         ; Salta para a rotina que efetivamente exibe os dígitos no display

; -------------------------------------------------------------------------
; Rotina de separação dos dígitos do cronômetro (modo 2)
usa_dados_cronometro:
    ; -------------------------------
    ; Separa os dígitos dos SEGUNDOS do cronômetro
    ; -------------------------------
    lds temp1, mode_2 + 1       ; Carrega os segundos do cronômetro (localizados em mode_2 + 1) em temp1
    ldi temp2, 10               ; Carrega 10 em temp2 para servir de divisor
    call dividir                ; Divide temp1 por 10: 
                                ; → temp1 = dezena dos segundos, temp2 = unidade dos segundos
    mov r23, temp2              ; Armazena a unidade dos segundos em r23
    mov r24, temp1              ; Armazena a dezena dos segundos em r24

    ; -------------------------------
    ; Separa os dígitos dos MINUTOS do cronômetro
    ; -------------------------------
    lds temp1, mode_2           ; Carrega os minutos do cronômetro (localizados em mode_2) para temp1
    ldi temp2, 10               ; Carrega 10 em temp2 para a divisão
    call dividir                ; Divide para separar os dígitos:
                                ; → temp1 = dezena dos minutos, temp2 = unidade dos minutos
    mov r25, temp2              ; Armazena a unidade dos minutos em r25
    mov r26, temp1              ; Armazena a dezena dos minutos em r26

    ; Resultado final para o cronômetro:
    ; r23 = Segundos Unidade, r24 = Segundos Dezena,
    ; r25 = Minutos Unidade, r26 = Minutos Dezena
    ; Estes valores serão usados para atualizar o display multiplexado
    rjmp exibir_valores         ; Salta para a rotina de exibição dos dígitos

; -------------------------------------------------------------------------
; Rotina para exibir os dígitos no display multiplexado
exibir_valores:
    ; -----------------------------------------------------------
    ; Exibe o dígito das UNIDADES dos SEGUNDOS (armazenado em r23)
    ; -----------------------------------------------------------
    mov temp1, r23              ; Move o dígito da unidade dos segundos para temp1
    rcall enviar_para_cd4511    ; Chama a rotina que envia o valor BCD para o driver CD4511
    in temp2, PORTB             ; Lê o valor atual do PORTB (controle dos displays)
    andi temp2, 0b11110000      ; Limpa os bits PB0 a PB3 (apaga a seleção atual de displays)
    ori temp2, (1 << PB3)       ; Define o bit PB3 para selecionar o display da unidade dos segundos
    out PORTB, temp2            ; Atualiza PORTB para acionar o display correspondente
    rcall delay_multiplex       ; Aguarda um curto atraso para que o dígito permaneça visível

    ; -----------------------------------------------------------
    ; Exibe o dígito das DEZENAS dos SEGUNDOS (armazenado em r24)
    ; -----------------------------------------------------------
    mov temp1, r24              ; Move o dígito da dezena dos segundos para temp1
    rcall enviar_para_cd4511    ; Envia o valor para o CD4511
    in temp2, PORTB             ; Lê o valor atual de PORTB
    andi temp2, 0b11110000      ; Limpa os bits PB0 a PB3
    ori temp2, (1 << PB2)       ; Define o bit PB2 para selecionar o display da dezena dos segundos
    out PORTB, temp2            ; Atualiza PORTB para acionar o display
    rcall delay_multiplex       ; Aguarda um curto atraso

    ; -----------------------------------------------------------
    ; Exibe o dígito das UNIDADES dos MINUTOS (armazenado em r25)
    ; -----------------------------------------------------------
    mov temp1, r25              ; Move o dígito da unidade dos minutos para temp1
    rcall enviar_para_cd4511    ; Envia o valor para o CD4511
    in temp2, PORTB             ; Lê o valor atual de PORTB
    andi temp2, 0b11110000      ; Limpa os bits de controle dos displays
    ori temp2, (1 << PB1)       ; Define o bit PB1 para selecionar o display da unidade dos minutos
    out PORTB, temp2            ; Atualiza PORTB para acionar o display
    rcall delay_multiplex       ; Aguarda um curto atraso

    ; -----------------------------------------------------------
    ; Exibe o dígito das DEZENAS dos MINUTOS (armazenado em r26)
    ; -----------------------------------------------------------
    mov temp1, r26              ; Move o dígito da dezena dos minutos para temp1
    rcall enviar_para_cd4511    ; Envia o valor para o CD4511
    in temp2, PORTB             ; Lê o valor atual de PORTB
    andi temp2, 0b11110000      ; Limpa os bits de seleção
    ori temp2, (1 << PB0)       ; Define o bit PB0 para selecionar o display da dezena dos minutos
    out PORTB, temp2            ; Atualiza PORTB para acionar o display
    rcall delay_multiplex       ; Aguarda um curto atraso para completar a multiplexação

    ret                         ; Retorna da sub-rotina de multiplexação

; -------------------------------------------------------------------------
; Rotina que envia um valor BCD para o driver CD4511 (através dos pinos PD2–PD5)
enviar_para_cd4511:
    lsl temp1                   ; Desloca temp1 para a esquerda uma vez (multiplica por 2)
    lsl temp1                   ; Desloca novamente (multiplica por 4), de forma a alinhar o valor com PD2–PD5
    in temp2, PORTD             ; Lê o valor atual de PORTD para preservar outros bits
    andi temp2, 0b11000011      ; Limpa os bits PD2 a PD5, reservados para o BCD
    or temp2, temp1             ; Combina o valor BCD (já deslocado) com os bits preservados de PORTD
    out PORTD, temp2            ; Atualiza PORTD, enviando o valor para o CD4511
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Rotina para efetuar uma divisão inteira por subtrações sucessivas
; Entrada: temp1 contém o dividendo e temp2 contém o divisor (10 neste caso)
; Após a chamada:
;   - temp1 contém o quociente (dezena)
;   - temp2 contém o resto (unidade)
dividir:
    push r19                    ; Salva r19 na pilha, que será usado como acumulador do quociente
    clr r19                     ; Zera r19 para iniciar a contagem do quociente
div_loop:
    cp temp1, temp2             ; Compara o dividendo (temp1) com o divisor (temp2)
    brlo fim_div                ; Se temp1 é menor que temp2, não é mais possível subtrair; termina a divisão
    sub temp1, temp2            ; Subtrai o divisor de temp1
    inc r19                   ; Incrementa o contador de quociente
    rjmp div_loop               ; Repete o loop enquanto temp1 for maior ou igual a temp2
fim_div:
    ; Após o loop, o que sobra em temp1 é o resto
    mov temp2, temp1            ; Move o resto para temp2 (representa a unidade)
    mov temp1, r19             ; Move o quociente (r19) para temp1 (representa a dezena)
    pop r19                     ; Restaura o valor de r19
    ret                         ; Retorna com: temp1 = dezena, temp2 = unidade

; -------------------------------------------------------------------------
; Rotina de atraso para a multiplexação dos displays
; Aguarda um curto intervalo de tempo para manter cada dígito visível.
delay_multiplex:
    push r24                    ; Salva r24, que será usado no contador
    push r25                    ; Salva r25, também usado no contador
    ldi r25, high(2500)         ; Carrega a parte alta do valor 5000 (constante de atraso)
    ldi r24, low(2500)          ; Carrega a parte baixa do valor 5000
delay_loop:
    sbiw r24, 1                ; Subtrai 1 do valor de r24:r25 (contador de atraso)
    brne delay_loop            ; Enquanto o contador não for zero, repete
    pop r25                   ; Restaura r25
    pop r24                   ; Restaura r24
    ret                       ; Retorna da rotina de atraso

; -------------------------
; Rotina de multiplexação específica para o MODO 3 (ajuste)
; Nesta rotina os dígitos são calculados como no relógio e, em seguida,
; é feito um controle de piscagem para destacar o dígito em ajuste.
multiplexar_display_modo3:
    ; -------------------------------
    ; Separa os dígitos dos SEGUNDOS (relógio) para o modo 3
    ; -------------------------------
    lds temp1, mode_1 + 1       ; Carrega os segundos do relógio
    ldi temp2, 10               ; Carrega 10 em temp2 para divisão
    call dividir                ; Divide: temp1 = dezena e temp2 = unidade dos segundos
    mov r23, temp2              ; Armazena a unidade dos segundos em r23
    mov r24, temp1              ; Armazena a dezena dos segundos em r24

    ; -------------------------------
    ; Separa os dígitos dos MINUTOS (relógio) para o modo 3
    ; -------------------------------
    lds temp1, mode_1           ; Carrega os minutos do relógio
    ldi temp2, 10               ; Prepara o divisor 10 em temp2
    call dividir                ; Divide: temp1 = dezena e temp2 = unidade dos minutos
    mov r25, temp2              ; Armazena a unidade dos minutos em r25
    mov r26, temp1              ; Armazena a dezena dos minutos em r26

    ; -------------------------------
    ; Atualiza o contador de piscagem
    ; -------------------------------
    lds temp1, blink_counter    ; Carrega o valor atual do contador de piscagem
    inc temp1                   ; Incrementa o contador para indicar passagem de ciclo
    cpi temp1, 150              ; Compara o contador com o limite para alternar a visibilidade
                                ; (limite maior → piscagem mais lenta)
    brlo salvar_contador        ; Se ainda não atingiu o limite, salta para salvar o valor
    ldi temp1, 0                ; Se atingiu ou excedeu, reseta o contador para 0
salvar_contador:
    sts blink_counter, temp1    ; Salva o novo valor do contador em blink_counter

    ; -------------------------------
    ; Verifica se o dígito em ajuste deve ser exibido ou apagado
    ; -------------------------------
    cpi temp1, 10               ; Compara o contador com 10 (metade do ciclo de piscagem)
    brlo exibe_normal           ; Se for menor, exibe normalmente o dígito
    ; Se o contador for maior ou igual a 10, o dígito em ajuste será apagado
    lds temp1, adjust_digit_selector ; Lê o seletor do dígito que está sendo ajustado (valor de 0 a 3)
    cpi temp1, 0               ; Verifica se é o dígito da unidade dos segundos
    brne testa_sd             ; Se não for, passa para o teste seguinte
    ldi r23, 10               ; Configura r23 com 10 para indicar que o dígito da unidade dos segundos deve ser apagado
    rjmp exibe_normal         ; Salta para a rotina de exibição (os demais dígitos continuam normalmente)

testa_sd:
    cpi temp1, 1               ; Verifica se o dígito ajustado é o da dezena dos segundos
    brne testa_mu             ; Se não for, passa para o próximo teste
    ldi r24, 10               ; Configura r24 com 10 para apagar a dezena dos segundos
    rjmp exibe_normal         ; Salta para exibir os demais dígitos normalmente

testa_mu:
    cpi temp1, 2               ; Verifica se o dígito ajustado é o da unidade dos minutos
    brne testa_md             ; Se não for, passa para o próximo teste
    ldi r25, 10               ; Configura r25 com 10 para apagar a unidade dos minutos
    rjmp exibe_normal         ; Salta para exibição normal dos demais dígitos

testa_md:
    cpi temp1, 3               ; Verifica se o dígito ajustado é o da dezena dos minutos
    brne exibe_normal         ; Se não for nenhum valor válido (0 a 3), segue exibindo normalmente
    ldi r26, 10               ; Configura r26 com 10 para apagar a dezena dos minutos

exibe_normal:
    ; -------------------------------
    ; Configura o Timer0 para a próxima alternância
    ; -------------------------------
    ldi temp1, (1 << CS02) | (0 << CS01) | (1 << CS00) ; Configura o prescaler do Timer0 para 1024
    out TCCR0B, temp1        ; Atualiza o registrador TCCR0B para iniciar o Timer0

    ; -------------------------------
    ; Exibe o dígito da UNIDADE dos SEGUNDOS (r23)
    ; -------------------------------
    mov temp1, r23                ; Move o valor de r23 para temp1
    cpi temp1, 10                 ; Verifica se o valor é 10 (comando para apagar o dígito)
    breq desliga_display_su       ; Se for 10, salta para a rotina que desliga este display
    rcall enviar_para_cd4511      ; Caso contrário, envia o valor (BCD) para o CD4511
    in temp2, PORTB               ; Lê o estado atual de PORTB
    andi temp2, 0b11110000        ; Limpa os bits PB0 a PB3 para selecionar o display
    ori temp2, (1 << PB3)         ; Ativa o display conectado a PB3 (unidade dos segundos)
    out PORTB, temp2              ; Atualiza PORTB para exibir o dígito
    rjmp continua_sd             ; Salta para a continuação da exibição dos outros dígitos

desliga_display_su:
    ; -------------------------------
    ; Desliga o display da unidade dos segundos (PB3)
    ; -------------------------------
    in temp2, PORTB               ; Lê o valor atual de PORTB
    andi temp2, 0b11110111        ; Zera o bit PB3 para desligar esse display
    out PORTB, temp2              ; Atualiza PORTB
    ; Continua para a exibição dos demais dígitos
continua_sd:
    ; -------------------------------
    ; Exibe o dígito da DEZENAS dos SEGUNDOS (r24)
    ; -------------------------------
    rcall delay_multiplex         ; Aguarda um curto intervalo
    mov temp1, r24                ; Move o valor da dezena dos segundos para temp1
    cpi temp1, 10                 ; Verifica se deve apagar o dígito (valor 10 indica ocultar)
    breq desliga_display_sd       ; Se for 10, desliga o display correspondente
    rcall enviar_para_cd4511      ; Caso contrário, envia o valor para o driver CD4511
    in temp2, PORTB               ; Lê o estado atual de PORTB
    andi temp2, 0b11110000        ; Limpa os bits de seleção dos displays
    ori temp2, (1 << PB2)         ; Ativa o display conectado a PB2 (dezena dos segundos)
    out PORTB, temp2              ; Atualiza PORTB para exibir o dígito
    rjmp continua_mu              ; Prossegue para exibir os dígitos dos minutos

desliga_display_sd:
    ; -------------------------------
    ; Desliga o display da dezena dos segundos (PB2)
    ; -------------------------------
    in temp2, PORTB               ; Lê PORTB
    andi temp2, 0b11111011        ; Zera o bit PB2, apagando este display
    out PORTB, temp2              ; Atualiza PORTB

continua_mu:
    ; -------------------------------
    ; Exibe o dígito da UNIDADE dos MINUTOS (r25)
    ; -------------------------------
    rcall delay_multiplex         ; Aguarda para estabilizar a multiplexação
    mov temp1, r25                ; Move o dígito da unidade dos minutos para temp1
    cpi temp1, 10                 ; Verifica se o valor é 10 (indicando que deve ser apagado)
    breq desliga_display_mu       ; Se for 10, desliga o display correspondente
    rcall enviar_para_cd4511      ; Envia o valor para o CD4511
    in temp2, PORTB               ; Lê o estado atual de PORTB
    andi temp2, 0b11110000        ; Limpa os bits PB0 a PB3
    ori temp2, (1 << PB1)         ; Ativa o display na saída PB1 (unidade dos minutos)
    out PORTB, temp2              ; Atualiza PORTB
    rjmp continua_md              ; Prossegue para a exibição dos dígitos restantes

desliga_display_mu:
    ; -------------------------------
    ; Desliga o display da unidade dos minutos (PB1)
    ; -------------------------------
    in temp2, PORTB               ; Lê PORTB
    andi temp2, 0b11111101        ; Zera o bit PB1, apagando este display
    out PORTB, temp2              ; Atualiza PORTB

continua_md:
    ; -------------------------------
    ; Exibe o dígito da DEZENAS dos MINUTOS (r26)
    ; -------------------------------
    rcall delay_multiplex         ; Aguarda um curto intervalo
    mov temp1, r26                ; Move o dígito da dezena dos minutos para temp1
    cpi temp1, 10                 ; Verifica se o dígito deve ser apagado (valor 10)
    breq desliga_display_md       ; Se for 10, desliga o display correspondente
    rcall enviar_para_cd4511      ; Caso contrário, envia o valor via CD4511
    in temp2, PORTB               ; Lê o estado atual de PORTB
    andi temp2, 0b11110000        ; Limpa os bits de controle dos displays
    ori temp2, (1 << PB0)         ; Ativa o display conectado a PB0 (dezena dos minutos)
    out PORTB, temp2              ; Atualiza PORTB para exibir o dígito
    rjmp fim_multiplex_modo3      ; Após exibir todos os dígitos, salta para o término

desliga_display_md:
    ; -------------------------------
    ; Desliga o display da dezena dos minutos (PB0)
    ; -------------------------------
    in temp2, PORTB               ; Lê o valor atual de PORTB
    andi temp2, 0b11111110        ; Zera o bit PB0, apagando este display
    out PORTB, temp2              ; Atualiza PORTB

fim_multiplex_modo3:
    ; -------------------------------
    ; Delay final para encerrar o ciclo de multiplexação
    ; -------------------------------
    rcall delay_multiplex         ; Aguarda um atraso extra para completar o ciclo
    ret                         ; Retorna da sub-rotina de multiplexação do modo 3
