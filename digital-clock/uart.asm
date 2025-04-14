; UART com Transmissão por Interrupção no ATmega328P

; ============================
; DSEG - Variáveis de Controle
; ============================
.dseg
uart_buffer:     .byte 64      ; Buffer circular de 64 bytes para armazenamento dos dados a serem enviados
uart_head:       .byte 1       ; Ponteiro de escrita no buffer (índice onde o próximo byte será armazenado)
uart_tail:       .byte 1       ; Ponteiro de leitura no buffer (índice do próximo byte a ser enviado)
uart_sending:    .byte 1       ; Flag que indica se a transmissão está em andamento (1 = enviando; 0 = parado)

; ============================
; CSEG - Código do Programa
; ============================
.cseg

; ============================
; CONFIGURAÇÃO USART (no RESET)
; ============================
; --- Dentro da rotina de reset (inicialização do sistema) ---
; Configura a taxa de baud e os parâmetros do protocolo serial

    ldi temp1, high(UBRR_VALUE)           ; Carrega o byte mais significativo do valor UBRR (definido pela baud rate desejada)
    sts UBRR0H, temp1                     ; Armazena no registrador UBRR0H (parte alta da taxa de baud)
    ldi temp1, low(UBRR_VALUE)            ; Carrega o byte menos significativo do UBRR_VALUE
    sts UBRR0L, temp1                     ; Armazena no registrador UBRR0L (parte baixa da taxa de baud)
    ldi temp1, (1 << TXEN0) | (1 << UDRIE0) ; Configura UCSR0B: Habilita a transmissão (TXEN0) e a interrupção de dado vazio (UDRIE0)
    sts UCSR0B, temp1                     ; Atualiza o registrador de controle UCSR0B com a configuração acima
    ldi temp1, (1 << UCSZ01) | (1 << UCSZ00) ; Configura UCSR0C: Define o formato dos dados (8 bits, sem paridade e 1 bit de parada)
    sts UCSR0C, temp1                     ; Atualiza o registrador de controle UCSR0C com a configuração acima

; ============================
; UART_Enqueue_Byte
; Descrição: Enfileira um byte (em r19) no buffer circular para transmissão via UART
; Entrada: r19 = byte a ser enviado
; ============================
UART_Enqueue_Byte:
    push temp1                  ; Salva o conteúdo de temp1
    push temp2                  ; Salva o conteúdo de temp2
    push r30                    ; Salva o registrador r30 (parte baixa do ponteiro Z)
    push r31                    ; Salva o registrador r31 (parte alta do ponteiro Z)

    lds temp1, uart_head        ; Carrega o valor atual do ponteiro de escrita (head) do buffer
    ldi temp2, 64               ; Define o tamanho máximo do buffer (64 bytes)
    inc temp1                   ; Incrementa o ponteiro de escrita para apontar para a próxima posição
    cp temp1, temp2             ; Compara com o tamanho do buffer para verificar overflow
    brlo no_wrap_uart           ; Se temp1 < 64, continua sem envolver
    ldi temp1, 0                ; Se ultrapassar 63, reinicia o ponteiro para 0 (wrap-around)
no_wrap_uart:
    sts uart_head, temp1        ; Atualiza o ponteiro de escrita do buffer

    ; Escreve o byte no buffer usando o ponteiro Z
    ldi ZH, high(uart_buffer)   ; Carrega a parte alta do endereço base do buffer
    ldi ZL, low(uart_buffer)    ; Carrega a parte baixa do endereço base do buffer
    add ZL, temp1              ; Adiciona o offset (índice do buffer) à parte baixa do ponteiro Z
    adc ZH, zero               ; Adiciona carry à parte alta do ponteiro Z, se necessário
    st Z, r19                  ; Armazena o byte (em r19) na posição calculada no buffer

    ; Inicia o envio se a transmissão não estiver em andamento
    lds temp2, uart_sending     ; Verifica a flag de transmissão atual
    cpi temp2, 0                ; Compara: 0 = não enviando
    brne uart_enqueue_exit      ; Se já estiver enviando, pula para o final
    ldi temp2, 1                ; Caso contrário, prepara o valor 1 para indicar que iniciaremos a transmissão
    sts uart_sending, temp2     ; Atualiza a flag, marcando que o envio está em andamento
    ldi temp2, (1 << TXEN0) | (1 << UDRIE0) ; Configura UCSR0B para manter o transmissor habilitado com interrupção
    sts UCSR0B, temp2           ; Atualiza o registrador UCSR0B para que a interrupção de dado vazio seja ativada

uart_enqueue_exit:
    pop r31                   ; Restaura r31
    pop r30                   ; Restaura r30
    pop temp2                 ; Restaura temp2
    pop temp1                 ; Restaura temp1
    ret                       ; Retorna da sub-rotina

; ============================
; USART_Transmit_String_Async
; Descrição: Envia uma string armazenada na Flash de forma assíncrona, byte a byte.
; Entrada: Z aponta para a string na memória Flash (string terminada com zero)
; ============================
USART_Transmit_String_Async:
    push r30                 ; Salva o registrador r30 (parte baixa do ponteiro Z)
    push r31                 ; Salva o registrador r31 (parte alta do ponteiro Z)

str_async_loop:
    lpm r19, Z+              ; Lê o byte da Flash apontado por Z e incrementa o ponteiro Z
    tst r19                  ; Testa se o byte lido é zero (indicador do fim da string)
    breq str_async_end       ; Se for zero, a string terminou; sai do loop
    rcall UART_Enqueue_Byte  ; Caso contrário, enfileira o byte lido para transmissão
    rjmp str_async_loop      ; Repete o loop para o próximo byte

str_async_end:
    pop r31                  ; Restaura o registrador r31
    pop r30                  ; Restaura o registrador r30
    ret                      ; Retorna da sub-rotina

; ============================
; Interrupção USART - UDRE0
; Descrição: Rotina de serviço de interrupção (ISR) acionada quando o registrador de dados (UDR0) está vazio.
;           Responsável por enviar o próximo byte do buffer, se houver.
; ============================
uart_udre_isr:
    push temp1               ; Salva temp1
    push temp2               ; Salva temp2
    push r19                 ; Salva r19 (será utilizado para armazenar byte a enviar)
    push r21                 ; Salva r21 (registrador auxiliar)
    push r22                 ; Salva r22 (registrador auxiliar)
    push r23                 ; Salva r23 (registrador auxiliar)

    lds temp1, uart_tail     ; Carrega o valor do ponteiro de leitura (tail)
    lds temp2, uart_head     ; Carrega o valor do ponteiro de escrita (head)
    cp temp1, temp2          ; Compara para verificar se o buffer está vazio
    breq uart_buffer_empty   ; Se head igual a tail, não há dados para enviar; vai para rotina de buffer vazio

    ; ============================
    ; Atualiza a posição de leitura (tail) do buffer circular
    ; ============================
    ldi temp2, 64            ; Define o tamanho do buffer (64 bytes)
    inc temp1                ; Avança o ponteiro de leitura para o próximo byte
    cp temp1, temp2          ; Verifica se chegou ao final do buffer
    brlo no_wrap_read        ; Se não chegou, continua sem envolver
    ldi temp1, 0             ; Se chegou ao final, reinicia o ponteiro para 0
no_wrap_read:
    sts uart_tail, temp1     ; Atualiza o ponteiro de leitura do buffer

    ; ============================
    ; Lê o byte do buffer circular e envia pela UART
    ; ============================
    ldi ZH, high(uart_buffer)  ; Carrega a parte alta do endereço base do buffer
    ldi ZL, low(uart_buffer)   ; Carrega a parte baixa do endereço base do buffer
    add ZL, temp1             ; Adiciona o offset (valor de tail) à parte baixa
    adc ZH, zero              ; Ajusta a parte alta, considerando possível carry
    ld r19, Z                 ; Lê o byte armazenado no buffer na posição apontada por Z

    sts UDR0, r19             ; Carrega o byte no registrador UDR0, iniciando a transmissão
    rjmp uart_isr_exit        ; Pula para o término da ISR

uart_buffer_empty:
    ; ============================
    ; Se o buffer estiver vazio, desativa a interrupção UDRE0
    ; ============================
    ldi temp1, (1 << TXEN0)   ; Prepara configuração mantendo o transmissor (TX) habilitado
    sts UCSR0B, temp1         ; Atualiza UCSR0B para desativar a interrupção UDRE0
    ldi temp1, 0              ; Prepara valor 0 para sinalizar que não há transmissão em andamento
    sts uart_sending, temp1   ; Atualiza a flag, marcando que a transmissão terminou

uart_isr_exit:
    pop r23                 ; Restaura r23
    pop r22                 ; Restaura r22
    pop r21                 ; Restaura r21
    pop r19                 ; Restaura r19
    pop temp2               ; Restaura temp2
    pop temp1               ; Restaura temp1
    reti                    ; Retorna da interrupção

; ============================
; Send_Decimal_Byte_Async
; Descrição: Converte um valor (0–99) contido em byte_val (r20) em dois dígitos ASCII e enfileira para envio
; Entrada: r20 = byte_val (valor decimal 0–99)
; Procedimento: Divide o valor em dezenas e unidades, converte para ASCII e envia
; ============================
Send_Decimal_Byte_Async:
    push temp1              ; Salva o valor de temp1
    push r17                ; Salva o registrador r17 (uso em cálculos)
    push r20                ; Salva o conteúdo original de r20 (byte_val)

    mov temp1, byte_val     ; Copia o byte_val para temp1 para preparar a divisão
    rcall div10             ; Chama a sub-rotina div10, que divide temp1 por 10 
                            ; Ao retornar: temp1 contém a dezena; temp2 contém a unidade

    mov ascii_H, temp1      ; Armazena o dígito das dezenas em ascii_H
    mov ascii_L, temp2      ; Armazena o dígito das unidades em ascii_L

    subi ascii_H, -0x30     ; Converte o valor da dezena para seu equivalente ASCII ('0' = 0x30)
    mov r19, ascii_H        ; Move o dígito convertido para r19 (pronto para envio)
    rcall UART_Enqueue_Byte ; Enfileira o dígito das dezenas para envio via UART

    subi ascii_L, -0x30     ; Converte o valor da unidade para ASCII
    mov r19, ascii_L        ; Move o dígito convertido para r19
    rcall UART_Enqueue_Byte ; Enfileira o dígito das unidades para envio

    pop r20                 ; Restaura r20
    pop r17                 ; Restaura r17
    pop temp1               ; Restaura temp1
    ret                     ; Retorna da sub-rotina

; ============================
; send_mode1 com UART assíncrona
; Descrição: Envia a mensagem formatada do modo 1 (relógio) na UART
; Formato: "[MODO 1] MM:SS" onde MM = minutos e SS = segundos
; ============================
send_mode1:
    ; --- Envia a string “[MODO 1]” ---
    ldi ZL, low(str_modo1<<1)         ; Carrega a parte baixa do endereço da string "[MODO 1]" na Flash
    ldi ZH, high(str_modo1<<1)        ; Carrega a parte alta do endereço da string
    rcall USART_Transmit_String_Async ; Envia a string de forma assíncrona

    ; --- Envia os minutos (MM) ---
    lds byte_val, mode_1              ; Carrega o valor dos minutos do relógio
    rcall Send_Decimal_Byte_Async     ; Converte o valor e enfileira para envio (formato de dois dígitos)

    ; --- Envia o caractere “:” ---
    ldi ZL, low(str_colon<<1)         ; Carrega o endereço da string ":" na Flash
    ldi ZH, high(str_colon<<1)         
    rcall USART_Transmit_String_Async ; Envia ":" pela UART

    ; --- Envia os segundos (SS) ---
    lds byte_val, mode_1+1            ; Carrega o valor dos segundos do relógio (próximo byte de mode_1)
    rcall Send_Decimal_Byte_Async     ; Converte e envia o valor como dois dígitos

    ; --- Finaliza com quebra de linha ---
    rjmp send_newline_and_exit        ; Pula para a rotina que envia \r\n e retorna

; ============================
; send_mode2 com UART assíncrona
; Descrição: Envia o estado do cronômetro na UART.
; Pode enviar uma das seguintes mensagens:
; "[MODO 2] RUN MM:SS", "[MODO 2] STOPPED MM:SS" ou "[MODO 2] ZERO"
; ============================
send_mode2:
    lds temp1, mode_2+2               ; Carrega a flag de ativação do cronômetro (posição 2 de mode_2)
    cpi temp1, 0                      ; Verifica se a flag está desativada (0 → não rodando)
    breq check_mode2_zero             ; Se flag = 0, verifica se cronômetro está zerado ou parado

    ; --- Cronômetro em execução: envia "[MODO 2] RUN MM:SS" ---
    ldi ZL, low(str_modo2_run<<1)     ; Carrega a parte baixa do endereço da string "[MODO 2] RUN"
    ldi ZH, high(str_modo2_run<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a string de forma assíncrona

    lds byte_val, mode_2             ; Carrega os minutos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os minutos convertidos em dois dígitos

    ldi ZL, low(str_colon<<1)         ; Carrega o endereço da string ":" para separação
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String_Async ; Envia o caractere ":"

    lds byte_val, mode_2+1           ; Carrega os segundos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os segundos como dois dígitos

    rjmp send_newline_and_exit       ; Finaliza com envio de quebra de linha e retorna

check_mode2_zero:
    lds temp1, mode_2              ; Carrega os minutos do cronômetro
    lds temp2, mode_2+1            ; Carrega os segundos do cronômetro
    or temp1, temp2                ; Verifica se ambos os valores são zero (resultado zero se ambos forem 0)
    brne mode2_stopped             ; Se não forem zero, o cronômetro está parado mas não zerado
    ; --- Cronômetro zerado: envia "[MODO 2] ZERO" ---
    ldi ZL, low(str_modo2_zero<<1) ; Carrega o endereço da string "[MODO 2] ZERO" (parte baixa)
    ldi ZH, high(str_modo2_zero<<1); Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a string "[MODO 2] ZERO"
    rjmp send_newline_and_exit     ; Finaliza com envio de quebra de linha e retorna

mode2_stopped:
    ; --- Cronômetro parado mas não zerado: envia "[MODO 2] STOPPED MM:SS" ---
    ldi ZL, low(str_modo2_stop<<1)   ; Carrega o endereço da string "[MODO 2] STOPPED" (parte baixa)
    ldi ZH, high(str_modo2_stop<<1)  ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a string "[MODO 2] STOPPED"
    
    lds byte_val, mode_2             ; Carrega os minutos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os minutos formatados

    ldi ZL, low(str_colon<<1)         ; Carrega o endereço da string ":" (parte baixa)
    ldi ZH, high(str_colon<<1)        ; Carrega a parte alta
    rcall USART_Transmit_String_Async ; Envia o caractere ":"

    lds byte_val, mode_2+1           ; Carrega os segundos do cronômetro
    rcall Send_Decimal_Byte_Async    ; Envia os segundos formatados

    rjmp send_newline_and_exit       ; Finaliza com envio de quebra de linha e retorna

; ============================
; send_mode3 com UART assíncrona
; Descrição: Envia uma mensagem indicando qual dígito está sendo ajustado no MODO 3.
; Dependendo do valor de adjust_digit_selector (0 a 3), é enviada uma string diferente.
; ============================
send_mode3:
    lds temp1, adjust_digit_selector ; Carrega o valor do seletor de dígitos (0 a 3)
    cpi temp1, 0                     ; Compara com 0
    breq send_m3_su                  ; Se igual a 0, envia mensagem para ajuste da unidade dos segundos
    cpi temp1, 1                     ; Compara com 1
    breq send_m3_sd                  ; Se igual a 1, envia mensagem para ajuste da dezena dos segundos
    cpi temp1, 2                     ; Compara com 2
    breq send_m3_mu                  ; Se igual a 2, envia mensagem para ajuste da unidade dos minutos
    cpi temp1, 3                     ; Compara com 3
    breq send_m3_md                  ; Se igual a 3, envia mensagem para ajuste da dezena dos minutos
    rjmp send_newline_and_exit        ; Se valor inválido, apenas envia nova linha

send_m3_su:
    ; --- Envia a string: "[MODO 3] Ajustando a unidade dos segundos" ---
    ldi ZL, low(str_modo3_su<<1)     ; Carrega a parte baixa do endereço da string na Flash
    ldi ZH, high(str_modo3_su<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a mensagem pela UART
    rjmp send_newline_and_exit       ; Finaliza com quebra de linha e retorna

send_m3_sd:
    ; --- Envia a string: "[MODO 3] Ajustando a dezena dos segundos" ---
    ldi ZL, low(str_modo3_sd<<1)     ; Carrega a parte baixa do endereço da string
    ldi ZH, high(str_modo3_sd<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a mensagem
    rjmp send_newline_and_exit       ; Finaliza com quebra de linha e retorna

send_m3_mu:
    ; --- Envia a string: "[MODO 3] Ajustando a unidade dos minutos" ---
    ldi ZL, low(str_modo3_mu<<1)     ; Carrega a parte baixa do endereço da string
    ldi ZH, high(str_modo3_mu<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a mensagem
    rjmp send_newline_and_exit       ; Finaliza com quebra de linha e retorna

send_m3_md:
    ; --- Envia a string: "[MODO 3] Ajustando a dezena dos minutos" ---
    ldi ZL, low(str_modo3_md<<1)     ; Carrega a parte baixa do endereço da string
    ldi ZH, high(str_modo3_md<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a mensagem
    rjmp send_newline_and_exit       ; Finaliza com quebra de linha e retorna

; ============================
; send_newline_and_exit
; Descrição: Envia um caractere de nova linha (quebra de linha: \r\n) para formatar a saída UART.
; ============================
send_newline_and_exit:
    ldi ZL, low(str_newline<<1)      ; Carrega a parte baixa do endereço da string "\r\n"
    ldi ZH, high(str_newline<<1)     ; Carrega a parte alta do endereço
    rcall USART_Transmit_String_Async ; Envia a sequência de nova linha pela UART
    ret                             ; Retorna da sub-rotina

; ============================
; div10
; Descrição: Rotina que divide o conteúdo de temp1 por 10.
; Entrada: temp1 contém o valor a ser dividido.
; Saída: Ao retornar, temp1 recebe o quociente (dezena) e temp2 recebe o resto (unidade).
; ============================
div10:
    clr temp2                       ; Zera temp2 para iniciar o acumulador do quociente
div10_loop:
    cpi temp1, 10                   ; Compara temp1 com 10
    brlo div10_end                  ; Se temp1 < 10, sai do loop (divisão completa)
    subi temp1, 10                  ; Subtrai 10 de temp1
    inc temp2                       ; Incrementa o acumulador (quociente)
    rjmp div10_loop                 ; Repete o loop enquanto temp1 for maior ou igual a 10

div10_end:
    push temp1                      ; Salva o valor restante (resto da divisão) temporariamente na pilha
    mov temp1, temp2                ; Move o quociente (dezena) para temp1
    pop temp2                       ; Recupera o resto (unidade) para temp2
    ret                             ; Retorna, deixando: temp1 = dezena e temp2 = unidade
