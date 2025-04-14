; =========================================================================
; FUNÇÕES DE ATUALIZAÇÃO
; =========================================================================

; -------------------------------------------------------------------------
; Função: hora_atual
; Finalidade: Atualiza os segundos e minutos do relógio (Modo 1).
;            Incrementa os segundos, e se necessário, os minutos.
hora_atual:
    push temp1                  ; Salva o registrador temp1 na pilha para preservar seu valor
    push temp2                  ; Salva o registrador temp2 na pilha

    lds temp2, mode_1 + 1       ; Carrega os segundos atuais do relógio (armazenados em mode_1+1) para temp2
    inc temp2                   ; Incrementa os segundos em 1
    cpi temp2, 60               ; Compara se os segundos atingiram 60
    brne save_seconds           ; Se os segundos forem menores que 60, vai para salvar os segundos

; Se os segundos chegaram a 60, então é necessário incrementar os minutos.
atualiza_minuto_atual:
    lds temp1, mode_1           ; Carrega os minutos atuais do relógio (armazenados em mode_1) para temp1
    inc temp1                   ; Incrementa os minutos em 1
    cpi temp1, 60               ; Compara se os minutos atingiram 60
    brne save_minutes          ; Se os minutos forem menores que 60, vai para salvar o novo valor
    ldi temp1, 0                ; Se os minutos chegaram a 60, zera os minutos (reinicia o contador)

save_minutes:
    sts mode_1, temp1           ; Salva os minutos atualizados de volta na memória (mode_1)
    ldi temp2, 0                ; Zera os segundos, pois um novo minuto foi iniciado

save_seconds:
    sts mode_1 + 1, temp2       ; Salva os segundos (atualizados) em mode_1+1
    pop temp2                   ; Restaura o valor original de temp2
    pop temp1                   ; Restaura o valor original de temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: cronometro
; Finalidade: Atualiza os segundos e minutos do cronômetro (Modo 2) somente se a flag
;             de ativação estiver marcada (1 = contando).
cronometro:
    push temp1                  ; Salva temp1 na pilha
    push temp2                  ; Salva temp2 na pilha

    lds temp1, mode_2 + 2       ; Lê a flag de ativação do cronômetro (armazenada em mode_2+2)
    cpi temp1, 0                ; Compara a flag com 0 (parado)
    breq crono_end              ; Se a flag for 0, sai sem atualizar (cronômetro parado)

    ; Se o cronômetro estiver ativo:
    lds temp2, mode_2 + 1       ; Carrega os segundos atuais do cronômetro (mode_2+1) para temp2
    inc temp2                   ; Incrementa os segundos em 1
    cpi temp2, 60               ; Compara se os segundos chegaram a 60
    brne crono_save_seconds     ; Se ainda não atingiu 60, pula para salvar os segundos

; Caso os segundos atinjam 60, incrementa os minutos.
atualiza_minuto_cronometro:
    lds temp1, mode_2           ; Carrega os minutos atuais do cronômetro (armazenados em mode_2)
    inc temp1                   ; Incrementa os minutos em 1
    cpi temp1, 60               ; Compara se os minutos atingiram 60
    brne crono_save_minutes     ; Se os minutos forem menores que 60, vai para salvar o novo valor
    ldi temp1, 0                ; Se ultrapassou 59, zera os minutos

crono_save_minutes:
    sts mode_2, temp1           ; Salva os minutos atualizados no cronômetro (mode_2)
    ldi temp2, 0                ; Zera os segundos para iniciar um novo minuto

crono_save_seconds:
    sts mode_2 + 1, temp2       ; Salva os segundos atualizados do cronômetro em mode_2+1

crono_end:
    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: handle_start_modo2
; Finalidade: Alterna a flag de ativação do cronômetro (Modo 2).
;            Se a flag estiver 0 (parado), muda para 1 (contando) e vice-versa.
handle_start_modo2:
    push temp1                  ; Salva temp1
    push temp2                  ; Salva temp2

    lds temp1, mode_2 + 2       ; Lê a flag de ativação do cronômetro
    ldi temp2, 1                ; Prepara o valor 1 para operação XOR
    eor temp1, temp2            ; Inverte o valor da flag (XOR com 1: 0→1 ou 1→0)
    sts mode_2 + 2, temp1       ; Salva a nova flag de ativação em mode_2+2

    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: handle_reset_modo2
; Finalidade: Reseta o cronômetro (Modo 2) somente se a flag de ativação indicar que
;             o cronômetro está parado (flag = 0). Emite um beep como confirmação.
handle_reset_modo2:
    push temp1                  ; Salva temp1
    push temp2                  ; Salva temp2

    lds temp1, mode_2 + 2       ; Lê a flag de ativação do cronômetro
    cpi temp1, 0                ; Verifica se o cronômetro está parado (flag = 0)
    brne pass_reset             ; Se estiver ativo, sai sem resetar
    ldi temp2, 0                ; Prepara 0 para resetar os valores
    sts mode_2, temp2           ; Zera os minutos do cronômetro (mode_2)
    sts mode_2 + 1, temp2       ; Zera os segundos do cronômetro (mode_2+1)
    rcall beep_modo             ; Emite um beep para confirmar a operação de reset

pass_reset:
    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: handle_start_modo3
; Finalidade: Avança para o próximo dígito a ser ajustado no Modo 3 (ajuste).
;            Essa função chama a rotina de navegação entre os dígitos.
handle_start_modo3:
    push temp1                  ; Salva temp1
    push temp2                  ; Salva temp2

    rcall navegar_digitos       ; Chama a rotina que alterna o dígito a ser ajustado (ciclo 0 → 1 → 2 → 3 → 0)

    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: handle_reset_modo3
; Finalidade: Incrementa o valor do dígito atualmente selecionado para ajuste no Modo 3.
;            Chama a rotina de ajuste para modificar o dígito.
handle_reset_modo3:
    push temp1                  ; Salva temp1
    push temp2                  ; Salva temp2

    rcall ajustar_digito        ; Chama a sub-rotina que incrementa o dígito selecionado

    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: navegar_digitos
; Finalidade: Avança para o próximo dígito a ser ajustado no Modo 3.
;            Cicla entre os valores 0, 1, 2 e 3.
navegar_digitos:
    lds temp1, adjust_digit_selector  ; Carrega o valor atual do seletor de dígitos (0 a 3)
    inc temp1                         ; Incrementa o seletor para o próximo dígito
    cpi temp1, 4                      ; Verifica se o novo valor ultrapassou 3 (existem 4 dígitos: 0 a 3)
    brlo salvar_digito_atual          ; Se ainda menor que 4, continua
    ldi temp1, 0                      ; Se ultrapassou, reinicia para 0 (ciclo completo)
salvar_digito_atual:
    sts adjust_digit_selector, temp1  ; Salva o novo seletor de dígitos na memória
    ret                               ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: ajustar_digito
; Finalidade: Ajusta (incrementa) o valor do dígito selecionado no Modo 3.
ajustar_digito:
    lds temp1, adjust_digit_selector  ; Carrega o seletor do dígito atual (0 a 3)
    cpi temp1, 0                      ; Verifica se o dígito a ajustar é a unidade dos segundos
    breq ajustar_su                 ; Se for 0, salta para a rotina de ajuste da unidade dos segundos
    cpi temp1, 1                      ; Compara para verificar se é a dezena dos segundos
    breq ajustar_sd                 ; Se for 1, salta para o ajuste da dezena dos segundos
    cpi temp1, 2                      ; Compara para verificar se é a unidade dos minutos
    breq ajustar_mu                 ; Se for 2, salta para o ajuste da unidade dos minutos
    cpi temp1, 3                      ; Compara para verificar se é a dezena dos minutos
    breq ajustar_md                 ; Se for 3, salta para o ajuste da dezena dos minutos
    ret                             ; Se o valor for inválido, apenas retorna

; -------------------------------------------------------------------------
; Função: ajustar_su
; Finalidade: Ajusta a unidade dos segundos (Modo 3).
ajustar_su:
    lds temp1, mode_1 + 1             ; Carrega os segundos atuais do relógio
    ldi temp2, 10
    rcall dividir                     ; Divide os segundos: após a divisão, temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade dos segundos
    cpi temp2, 10                     ; Verifica se a unidade chegou a 10
    brlo salvar_su                    ; Se for menor que 10, prossegue com a gravação
    ldi temp2, 0                      ; Se for 10, reinicia para 0
salvar_su:
    ; Recalcula os segundos: (dezena * 10) + unidade
    ldi r23, 10
    mul temp1, r23                    ; Multiplica a dezena (temp1) por 10; o resultado fica em r1:r0
    mov temp1, r0                     ; Move o resultado (parte baixa) para temp1
    add temp1, temp2                  ; Soma a unidade (temp2) ao resultado
    sts mode_1 + 1, temp1             ; Salva os segundos atualizados de volta em mode_1+1
    ret                             ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: ajustar_sd
; Finalidade: Ajusta a dezena dos segundos (Modo 3).
ajustar_sd:
    lds temp1, mode_1 + 1             ; Carrega os segundos atuais
    ldi temp2, 10
    rcall dividir                     ; Divide os segundos: temp1 = dezena, temp2 = unidade
    inc temp1                         ; Incrementa a dezena dos segundos
    cpi temp1, 6                      ; Limita a dezena máxima a 5 (para 59 segundos)
    brlo salvar_sd                    ; Se a dezena for menor que 6, continua
    ldi temp1, 0                      ; Se ultrapassar, reinicia para 0
salvar_sd:
    ; Recalcula os segundos: (dezena * 10) + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1 + 1, temp1             ; Salva os segundos atualizados
    ret                             ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: ajustar_mu
; Finalidade: Ajusta a unidade dos minutos (Modo 3).
ajustar_mu:
    lds temp1, mode_1                 ; Carrega os minutos atuais
    ldi temp2, 10
    rcall dividir                     ; Divide os minutos: temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade dos minutos
    cpi temp2, 10                     ; Verifica se atingiu 10
    brlo salvar_mu                    ; Se for menor, continua
    ldi temp2, 0                      ; Se for igual a 10, zera a unidade
salvar_mu:
    ; Recalcula os minutos: (dezena * 10) + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1, temp1                 ; Salva os minutos atualizados em mode_1
    ret                             ; Retorna da sub-rotina

; -------------------------------------------------------------------------
; Função: ajustar_md
; Finalidade: Ajusta a dezena dos minutos (Modo 3).
ajustar_md:
    lds temp1, mode_1                 ; Carrega os minutos atuais
    ldi temp2, 10
    rcall dividir                     ; Divide os minutos: temp1 = dezena, temp2 = unidade
    inc temp1                         ; Incrementa a dezena dos minutos
    cpi temp1, 6                      ; Limita a dezena máxima a 5 (para 59 minutos)
    brlo salvar_md                    ; Se a dezena for menor que 6, continua
    ldi temp1, 0                      ; Se ultrapassar 5, reinicia para 0
salvar_md:
    ; Recalcula os minutos: (dezena * 10) + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1, temp1                 ; Salva os minutos atualizados em mode_1
    ret                             ; Retorna da sub-rotina
