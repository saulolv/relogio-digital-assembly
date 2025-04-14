; =========================================================================
; FUN��ES DE ATUALIZA��O
; =========================================================================
hora_atual:
    push temp1               ; Salva registradores tempor�rios
    push temp2
    lds temp2, mode_1 + 1    ; Carrega segundos atuais do rel�gio
    inc temp2                ; Incrementa 1 segundo
    cpi temp2, 60            ; Verifica se chegou a 60 segundos
    brne save_seconds        ; Se n�o, s� salva os segundos
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
    ret                      ; Retorna da fun��o

cronometro:
    push temp1               ; Salva registradores tempor�rios
    push temp2
    lds temp1, mode_2 + 2    ; L� a flag de ativa��o do cron�metro
    cpi temp1, 0
    breq crono_end           ; Se for 0, cron�metro est� desligado -> sai
    ; Se chegou aqui, cron�metro est� ativo
    lds temp2, mode_2 + 1    ; L� os segundos do cron�metro
    inc temp2                ; Incrementa 1 segundo
    cpi temp2, 60
    brne crono_save_seconds  ; Se n�o chegou a 60, s� salva os segundos
atualiza_minuto_cronometro:
    lds temp1, mode_2        ; L� os minutos
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
    ret                      ; Retorna da fun��o

handle_start_modo2:
    push temp1
    push temp2

    lds temp1, mode_2 + 2    ; Carrega flag de ativa��o do cron�metro
    ldi temp2, 1
    eor temp1, temp2         ; Inverte entre 0 ? 1
    sts mode_2 + 2, temp1    ; Salva de volta na posi��o correta

    pop temp2
    pop temp1
    ret

handle_reset_modo2:
    push temp1
	push temp2

	lds temp1, mode_2 + 2 
	cpi temp1, 0
	brne pass_reset

	ldi temp2, 0
	sts mode_2, temp2         ; Zera os minutos do cron�metro (mode_2 = 0)
	sts mode_2 + 1, temp2     ; Zera os segundos do cron�metro (mode_2 + 1 = 0)

	pass_reset:
	pop temp2
	pop temp1
    ret

handle_start_modo3:
    push temp1
	push temp2

	rcall navegar_digitos

	pop temp2
	pop temp1
    ret

handle_reset_modo3:
	push temp1
	push temp2

    rcall ajustar_digito

	pop temp2
	pop temp1
    ret

navegar_digitos:
    lds temp1, adjust_digit_selector  ; Carrega o valor atual do seletor de d�gitos
    inc temp1                        ; Incrementa para o pr�ximo d�gito
    cpi temp1, 4                     ; Verifica se chegou ao limite (4 d�gitos: 0,1,2,3)
    brlo salvar_digito_atual         ; Se for menor que 4, salva o novo valor
    ldi temp1, 0                     ; Se chegou a 4, volta para o primeiro d�gito (0)
salvar_digito_atual:
    sts adjust_digit_selector, temp1  ; Salva o novo valor do seletor de d�gitos
	ret


; Fun��es de ajuste corrigidas para o modo 3
; ============================================================
; FUN��O: ajustar_digito
; Finalidade: Ajusta o valor do d�gito selecionado no Modo 3
; ============================================================
ajustar_digito:
    lds temp1, adjust_digit_selector  ; Carrega o seletor de d�gitos atual
    cpi temp1, 0                      ; Verifica qual d�gito est� selecionado
    breq ajustar_su                   ; Unidade dos segundos
    cpi temp1, 1
    breq ajustar_sd                   ; Dezena dos segundos
    cpi temp1, 2
    breq ajustar_mu                   ; Unidade dos minutos
    cpi temp1, 3
    breq ajustar_md                   ; Dezena dos minutos
    ret                               ; Retorna se valor inv�lido

ajustar_su:
    ; Ajusta a unidade dos segundos
    lds temp1, mode_1 + 1             ; Carrega os segundos atuais
    ldi temp2, 10
    rcall dividir                     ; temp1 = dezena, temp2 = unidade
    inc temp2                         ; Incrementa a unidade
    cpi temp2, 10                     ; Verifica se passou de 9
    brlo salvar_su                    ; Se n�o passou, salva
    ldi temp2, 0                      ; Se passou, volta para 0
salvar_su:
    ; Recalcula o valor bin�rio: dezena*10 + unidade
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
    brlo salvar_sd                    ; Se n�o passou, salva
    ldi temp1, 0                      ; Se passou, volta para 0
salvar_sd:
    ; Recalcula o valor bin�rio: dezena*10 + unidade
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
    brlo salvar_mu                    ; Se n�o passou, salva
    ldi temp2, 0                      ; Se passou, volta para 0
salvar_mu:
    ; Recalcula o valor bin�rio: dezena*10 + unidade
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
    brlo salvar_md                    ; Se n�o passou, salva
    ldi temp1, 0                      ; Se passou, volta para 0
salvar_md:
    ; Recalcula o valor bin�rio: dezena*10 + unidade
    ldi r23, 10
    mul temp1, r23                    ; r1:r0 = dezena * 10
    mov temp1, r0                     ; temp1 = dezena * 10
    add temp1, temp2                  ; temp1 = (dezena * 10) + unidade
    sts mode_1, temp1                 ; Salva o novo valor dos minutos
    ret