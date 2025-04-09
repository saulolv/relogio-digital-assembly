# relogio-digital-assembly

## Objetivo

Implementar em assembly do AVR um código que simule o funcionamento de um relógio digital que marca os minutos e os segundos.

## Equipamentos

- 4x Displays 7 segmentos para mostrar minutos e segundos (MM SS)
- 3x Botões para acionar as funcionalidades (MODE, RESET, START)
- 1x Buzzer para sinalizar algumas ações

## Requisitos

- Considerar três modos de operação para o relógio
- Implementar contagem de tempo com timer e interrupção
- Implementar botões usando interrupção
- Imprimir pela serial informações de debug

## Modos de Operação

### MODO 1: Apresentação do tempo

- Estado inicial, ou quando estiver no MODO 3 e apertar MODE
- A cada segundo incrementa o tempo
- Imprime na serial, a cada segundo, a string "[MODO 1] MM:SS"

### MODO 2: Cronômetro

- No MODO 1 aperta MODE. O Buzzer faz um "bip"
- Zera os valores do display
- START inicia/para o cronômetro. O Buzzer faz um "bip"
- RESET zera o cronômetro se a contagem estiver parada. O Buzzer faz um "bip"
- Imprime na serial as seguintes strings de acordo com o funcionamento: "[MODO 2] ZERO", "[MODO 2] START" e "[MODO 2] RESET"

### MODO 3: Ajustar hora

- No MODO 2 aperta MODE. O Buzzer faz um "bip"
- START para andar pelo display
- Pisca número selecionado
- RESET para ajustar hora
- Imprime na serial as seguintes strings de acordo com o funcionamento: "[MODO 3] Ajustando a unidade dos segundos",  "[MODO 3] Ajustando a dezena dos segundos  ", "[MODO 3] Ajustando a unidade dos dos minutos" e "[MODO 3]  Ajustando a dezena dos dos minutos".

## Implementação

### Timer e Interrupção

O código utiliza um timer e interrupções para contar o tempo e alternar entre os modos de operação. O timer é configurado para gerar uma interrupção a cada segundo, que é usada para incrementar o tempo no modo de apresentação e para controlar o cronômetro.

### Botões

Os botões são implementados usando interrupções. Cada botão aciona uma interrupção que altera o modo de operação ou controla o cronômetro.

### Debug Serial

O código imprime informações de debug pela serial, permitindo monitorar o funcionamento do relógio e dos modos de operação. As strings de debug são impressas a cada segundo no modo de apresentação e de acordo com as ações no modo cronômetro e ajuste de hora.
