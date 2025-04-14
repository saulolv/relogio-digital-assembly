; =========================================================================
; FUNÇÕES DE ATUALIZAÇÃO
; =========================================================================

hora_atual:
    ; ================================
    ; Atualiza os segundos e minutos do relógio (modo 1)
    ; ================================

    push temp1                  ; Salva registrador temp1 na pilha
    push temp2                  ; Salva registrador temp2 na pilha

    lds temp2, mode_1 + 1       ; Carrega os segundos atuais do relógio
    inc temp2                   ; Incrementa 1 segundo
    cpi temp2, 60               ; Verifica se chegou a 60 segundos
    brne save_seconds           ; Se ainda não chegou a 60, salva e retorna

atualiza_minuto_atual:
    lds temp1, mode_1           ; Carrega os minutos atuais
    inc temp1                   ; Incrementa 1 minuto
    cpi temp1, 60               ; Verifica se chegou a 60 minutos
    brne save_minutes           ; Se não chegou, salva o valor
    ldi temp1, 0                ; Zera os minutos se chegou a 60

save_minutes:
    sts mode_1, temp1           ; Salva os minutos atualizados
    ldi temp2, 0                ; Zera os segundos (novo minuto iniciado)

save_seconds:
    sts mode_1 + 1, temp2       ; Salva os segundos atualizados
    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina

; -------------------------------------------------------------------------

cronometro:
    ; ================================
    ; Atualiza os segundos e minutos do cronômetro (modo 2)
    ; Só atualiza se a flag estiver ativada
    ; ================================

    push temp1                  ; Salva registrador temp1
    push temp2                  ; Salva registrador temp2

    lds temp1, mode_2 + 2       ; Lê a flag de ativação do cronômetro (0 = parado, 1 = contando)
    cpi temp1, 0
    breq crono_end              ; Se estiver parado, sai da função

    ; Se chegou aqui, o cronômetro está ativo

    lds temp2, mode_2 + 1       ; Lê os segundos atuais do cronômetro
    inc temp2                   ; Incrementa 1 segundo
    cpi temp2, 60               ; Verifica se chegou a 60 segundos
    brne crono_save_seconds     ; Se ainda não chegou a 60, apenas salva

atualiza_minuto_cronometro:
    lds temp1, mode_2           ; Lê os minutos atuais do cronômetro
    inc temp1                   ; Incrementa 1 minuto
    cpi temp1, 60               ; Verifica se chegou a 60 minutos
    brne crono_save_minutes     ; Se não, salva o novo valor
    ldi temp1, 0                ; Zera os minutos se passou de 59

crono_save_minutes:
    sts mode_2, temp1           ; Salva os minutos atualizados
    ldi temp2, 0                ; Zera os segundos para o novo minuto

crono_save_seconds:
    sts mode_2 + 1, temp2       ; Salva os segundos atualizados

crono_end:
    pop temp2                   ; Restaura temp2
    pop temp1                   ; Restaura temp1
    ret                         ; Retorna da sub-rotina
handle_start_modo2:
    ; ================================
    ; Alterna a flag de ativação do cronômetro (modo 2)
    ; ================================

    push temp1                   ; Salva registrador temp1
    push temp2                   ; Salva registrador temp2

    lds temp1, mode_2 + 2        ; Lê a flag de ativação (0 = parado, 1 = contando)
    ldi temp2, 1
    eor temp1, temp2             ; Inverte o bit (XOR com 1 → alterna 0↔1)
    sts mode_2 + 2, temp1        ; Salva o novo valor da flag

    pop temp2                    ; Restaura temp2
    pop temp1                    ; Restaura temp1
    ret                          ; Retorna da sub-rotina

; -------------------------------------------------------------------------

handle_reset_modo2:
    ; ================================
    ; Reseta o cronômetro (modo 2) somente se estiver parado
    ; ================================

    push temp1
    push temp2

    lds temp1, mode_2 + 2        ; Lê a flag de ativação do cronômetro
    cpi temp1, 0
    brne pass_reset              ; Se estiver rodando, não reseta

    ldi temp2, 0
    sts mode_2, temp2            ; Zera os minutos
    sts mode_2 + 1, temp2        ; Zera os segundos
    rcall beep_modo              ; Emite beep de confirmação

pass_reset:
    pop temp2
    pop temp1
    ret

; -------------------------------------------------------------------------

handle_start_modo3:
    ; ================================
    ; Avança para o próximo dígito a ser ajustado (modo 3)
    ; ================================

    push temp1
    push temp2

    rcall navegar_digitos        ; Muda o seletor de ajuste (0 → 1 → 2 → 3 → 0)

    pop temp2
    pop temp1
    ret

; -------------------------------------------------------------------------

handle_reset_modo3:
    ; ================================
    ; Incrementa o valor do dígito selecionado (modo 3)
    ; ================================

    push temp1
    push temp2

    rcall ajustar_digito         ; Incrementa o dígito conforme o seletor atual

    pop temp2
    pop temp1
    ret

    navegar_digitos:
    ; ================================
    ; Avança para o próximo dígito a ser ajustado (modo 3)
    ; Ciclo: 0 → 1 → 2 → 3 → 0
    ; ================================

    lds temp1, adjust_digit_selector  ; Carrega o valor atual do seletor de dígitos (0 a 3)
    inc temp1                         ; Avança para o próximo dígito

    cpi temp1, 4                      ; Verifica se passou do último (existem 4 dígitos: 0,1,2,3)
    brlo salvar_digito_atual          ; Se for menor que 4, continua normalmente

    ldi temp1, 0                      ; Se chegou a 4, reinicia o ciclo para o dígito 0

salvar_digito_atual:
    sts adjust_digit_selector, temp1  ; Salva o novo dígito selecionado
    ret                               ; Retorna da sub-rotina


; ============================================================
; FUNÇÃO: ajustar_digito
; Finalidade: Ajusta o valor do dígito selecionado no Modo 3
; ============================================================

ajustar_digito:
    ; ================================
    ; Verifica qual dígito está sendo ajustado (0 a 3)
    ; ================================

    lds temp1, adjust_digit_selector  ; Carrega o seletor de dígitos atual
    cpi temp1, 0                      ; Verifica se é a unidade dos segundos
    breq ajustar_su
    cpi temp1, 1                      ; Verifica se é a dezena dos segundos
    breq ajustar_sd
    cpi temp1, 2                      ; Verifica se é a unidade dos minutos
    breq ajustar_mu
    cpi temp1, 3                      ; Verifica se é a dezena dos minutos
    breq ajustar_md
    ret                               ; Retorna se o valor for inválido

; -------------------------------------------------------------------------

ajustar_su:
    ; ================================
    ; Ajusta a unidade dos segundos
    ; ================================

    lds temp1, mode_1 + 1             ; Carrega os segundos atuais
    ldi temp2, 10
    rcall dividir                     ; → temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade
    cpi temp2, 10
    brlo salvar_su                    ; Se < 10, continua
    ldi temp2, 0                      ; Se passou, reinicia em 0

salvar_su:
    ; Recalcula segundos: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = resultado (parte baixa)
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1 + 1, temp1             ; Salva segundos atualizados
    ret

; -------------------------------------------------------------------------

ajustar_sd:
    ; ================================
    ; Ajusta a dezena dos segundos
    ; ================================

    lds temp1, mode_1 + 1
    ldi temp2, 10
    rcall dividir                     ; → temp1 = dezena, temp2 = unidade
    inc temp1                         ; Incrementa a dezena
    cpi temp1, 6                      ; Máximo: 5 (para 59 segundos)
    brlo salvar_sd
    ldi temp1, 0                      ; Se passou, volta para 0

salvar_sd:
    ; Recalcula segundos: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1 + 1, temp1
    ret

; -------------------------------------------------------------------------

ajustar_mu:
    ; ================================
    ; Ajusta a unidade dos minutos
    ; ================================

    lds temp1, mode_1
    ldi temp2, 10
    rcall dividir                     ; → temp1 = dezena, temp2 = unidade
    inc temp2
    cpi temp2, 10
    brlo salvar_mu
    ldi temp2, 0

salvar_mu:
    ; Recalcula minutos: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1, temp1
    ret

; -------------------------------------------------------------------------

ajustar_md:
    ; ================================
    ; Ajusta a dezena dos minutos
    ; ================================

    lds temp1, mode_1
    ldi temp2, 10
    rcall dividir                     ; → temp1 = dezena, temp2 = unidade
    inc temp1
    cpi temp1, 6                      ; Máximo: 5 (para 59 minutos)
    brlo salvar_md
    ldi temp1, 0

salvar_md:
    ; Recalcula minutos: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23
    mov temp1, r0
    add temp1, temp2
    sts mode_1, temp1
    ret
