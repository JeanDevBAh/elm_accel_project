# Marco 1 — Co-processador ELM em FPGA

Disciplina: TEC 499 — MI Sistemas Digitais

Instituição: Universidade Estadual de Feira de Santana (UEFS)

Integrantes: Thiago Reis, Tairone Lima, Jean Carlos

Tutor: Wild Freitas

## 1. Definição do Problema

Este projeto implementa, em FPGA, um co-processador para inferência de uma rede neural baseada em Extreme Learning Machine (ELM). O sistema completo do problema é dividido em três partes: um núcleo classificador em FPGA, um driver Linux em ARM com acesso por MMIO e uma aplicação em C. Neste Marco 01, o foco é a construção e validação do IP de inferência em RTL, incluindo simulação e demonstração do funcionamento na placa DE1-SoC. A inferência da ELM foi tratada como uma sequência de quatro etapas: leitura da imagem de entrada, processamento da camada oculta, processamento da camada de saída e cálculo da predição por argmax. O problema especifica que a entrada é uma imagem em escala de cinza de 28×28 pixels, com 784 bytes, e que a saída é um dígito inteiro no intervalo [0,9].

## 2. Levantamento de Requisitos

O Marco 01 exige um coprocessador ELM em Verilog com arquitetura sequencial, contendo:

- FSM de controle.
- Datapath MAC (multiplica-acumula).
- Ativação aproximada (LUT ou piecewise linear).
- Argmax final. 
- Memórias para armazenamento dos dados.
- Banco de registradores.
- Representação em ponto fixo `Q4.12`.
- Estratégia clara para armazenamento e acesso a `W_in, b e β`.

Além disso, o enunciado exige para o repositório do Marco 01:

- RTL Verilog do IP `elm_accel`.
- Testbench com vetores de teste comparando com golden model.
- Diagrama de blocos do datapath e da FSM.
- Uso de recursos FPGA.
- Mapa preliminar de registradores.
- Scripts para automação dos testes.
- READ.ME com detalhamento da solução, ambiente, testes e análise dos resultados.

### E/S
- Receber imagem 28×28 pixels (784 bytes, 8 bits/pixel, escala de cinza).
- Calcular camada oculta: `h = sigmoid(W_in · x + b)`, com 128 neurônios.
- Calcular camada de saída: `y = β · h`, com 10 classes.
- Retornar a predição via `pred = argmax(y)` → inteiro 0..9.
- Sinalizar `busy`, `done` e `error` ao controlador externo.
- Expor contador de ciclos (`cycles`) para medição de desempenho.

---

## 3. Ambiente de Desenvolvimento

### Software
| Ferramenta | Versão | Uso |
|:---|:---|:---|
| **Intel Quartus Prime** | 21.1 Lite | Síntese, place-and-route e análise de recursos. |
| **Icarus Verilog** | 12.0+ | Compilação e simulação funcional do código RTL. |
| **GTKWave** | 3.3+ | Visualização de formas de onda para depuração de sinais. |
| **Python** | 3.10+ | Geração de arquivos MIF/HEX e execução do Golden Model. |
| **NumPy** | 1.24+ | Validação matemática dos resultados de inferência. |

### Hardware

| Componente | Descrição |
|------------|-----------|
| DE1-SoC | Placa com Cyclone V (5CSEMA5F31C6) + ARM Cortex-A9 |
| USB-Blaster | Programação da FPGA via JTAG |


---


## Mapa Preliminar de Registradores para futura interface MMIO (Marco 02)

> Mapa preliminar para referência. A interface MMIO ainda **não está implementada** no Marco 01.
> Nesta etapa, o co-processador é controlado por uma interface compacta de bancada com switches e botões.
> No Marco 02, essa lógica será associada ao acesso via MMIO entre HPS e FPGA.

## 4. Mapa de Registradores (Preliminar)

A comunicação futura via MMIO (Memory-Mapped I/O) poderá utilizar os seguintes registradores para controle pelo processador ARM:

| Endereço Relativo | Nome         | Acesso | Descrição |
|:--:|:-------------|:-----:|:----------|
| `0x00` | `REG_CTRL`   | R/W | Registrador de controle da operação. No Marco 02, deverá concentrar os comandos de controle, como seleção da operação e disparo da execução. |
| `0x04` | `REG_STATUS` | R   | Status do coprocessador: bits de `BUSY`, `DONE`, `ERROR` e campo da predição atual. |
| `0x08` | `REG_ADDR`   | R/W | Endereço para acesso às memórias internas. Será usado para apontar posições de imagem, pesos, bias ou beta. |
| `0x0C` | `REG_WDATA`  | R/W | Dado de escrita para alimentação das memórias internas. |
| `0x10` | `REG_RESULT` | R   | Resultado final da inferência, correspondente à predição `pred`. |
| `0x14` | `REG_CYCLES` | R   | Contador de ciclos de clock da inferência, usado para métricas de latência. |
| `0x18` | `REG_DEBUG`  | R   | Registrador auxiliar de depuração para observação interna do hardware. |

---

## 4.1 Conjunto de Instruções (ISA)

O co-processador implementa **operações controladas por um opcode de 3 bits**.  
No **Marco 01**, essas operações são demonstradas por meio de uma **interface compacta de bancada com switches** e com o banco de registradores preliminar.  
No **Marco 02**, elas serão associadas a uma interface **MMIO**.

| Opcode | Mnemônico      | Código | Descrição |
|:------:|:---------------|:------:|:----------|
| `3'b000` | `NOP`          | 0 | Nenhuma operação. Mantém o estado atual do co-processador. |
| `3'b001` | `STORE_IMG`    | 1 | Armazena um pixel na memória de imagem no endereço especificado. **Na interface atual de bancada**, o dado manual é limitado a **3 bits (0 a 7)** e expandido internamente para 8 bits. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b010` | `STORE_WEIGHT` | 2 | Armazena um peso `W_in` na memória de pesos no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para um valor reduzido em **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b011` | `STORE_BIAS`   | 3 | Armazena um valor de bias `b` na memória de bias no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b100` | `START`        | 4 | Inicia o processamento da inferência com os dados atualmente carregados nas memórias. Ativa o sinal `busy` até a conclusão. |
| `3'b101` | `STATUS`       | 5 | Leitura do estado atual do co-processador. Retorna os bits `busy`, `done` e `error`, além do resultado da predição `(0..9)` codificado em 4 bits no campo `pred` do status. |
| `3'b110` | `STORE_BETA`   | 6 | Armazena um peso `β` na memória de saída no endereço especificado. **Na interface atual de bancada**, o dado manual de 3 bits é convertido por tabela para **Q4.12** antes da escrita. A operação é bloqueada se `busy` ou `protect_inference` estiver ativo. |
| `3'b111` | `RESERVADO`    | 7 | Opcode reservado para extensões futuras da interface. Na implementação atual, não é utilizado como instrução válida da ISA. |


---



## 5. Diagrama de Blocos

O diagrama de blocos do datapath e da FSM está disponível em [`docs/diagrama_blocos.svg`](hardware/docs/Datapah+FSM.drawio.svg).

![Diagrama de Blocos](hardware/docs/Datapah+FSM.drawio.svg)



## 6. Instalação e Configuração do Ambiente

### Especificação do Hardware

Para a validação e testes do co-processador ELM, foi utilizada a plataforma de
desenvolvimento DE1-SoC, que integra um sistema SoC Altera Cyclone V. Esta
arquitetura heterogênea permite a cooperação entre processamento baseado em
software (ARM) e hardware reconfigurável (FPGA).

**Componentes Principais:**

- **FPGA:** Cyclone V 5CSEMA5F31C6
- **Lógica:** 32.070 ALMs (Adaptive Logic Modules)
- **Memória:** 3.971 Kbits de memória embarcada (M10K)
- **DSP:** 87 blocos de hardware para processamento digital de sinais
- **HPS:** Processador ARM Cortex-A9 Dual-Core
- **Interface de Programação:** USB-Blaster integrada para configuração via JTAG

**Periféricos de Interface Utilizados:**

- **Switches (SW[0-9]):** Utilizados para entrada manual de dados, opcodes e
ativação da proteção de escrita de memória.
- **Push-buttons (KEY[0-1]):** Mapeados para as funções de Reset do sistema e
pulso de execução de instruções.
- **Displays de 7 Segmentos (HEX0-5):** Utilizados para monitoramento em tempo
real da predição (argmax), estado da FSM (Busy/Done/Error) e contagem de ciclos
de performance.

---

### Configuração do Ambiente de Desenvolvimento

O processo de configuração do ambiente é dividido entre as ferramentas de síntese
de hardware e as ferramentas de validação por software.

**Requisitos de Software:**

- **Intel Quartus Prime Lite Edition (v21.1 ou superior):** Necessário para
síntese, place-and-route e geração do arquivo de programação (`.sof`) para a FPGA.
- **Golden Model e geração de vetores de teste (`.mif`/`.hex`):** Instale as
dependências com:

```bash
pip install numpy
pip install Pillow
```

**Procedimento de Configuração:**

**1. Clonagem do Repositório:**
```bash
git clone https://github.com/JeanDevBAh/elm_accel_project.git
```

**2. Programação da FPGA:**
1. Abra o projeto `.qpf` no Quartus Prime.
2. Execute a compilação completa para gerar o relatório de uso de recursos.
3. Conecte a placa DE1-SoC via USB e utilize o Programmer para carregar o
co-processador na FPGA.

## 7. Uso de Recursos FPGA

> Tabela a ser preenchida após síntese no Quartus Prime.

| Recurso | Utilizado | Disponível (Cyclone V) | % |
|---------|-----------|------------------------|---|
| LUTs | 1451 | 32.070 | ~4,5% |
| Flip-Flops | 2576 | 64.140 | ~4.0% |
| DSP Blocks | 2 | 87 | ~2.3% |
| M10K (BRAM) | 202 | 397 | ~50.8% |

---
## 8. Testes e Validação

### Scripts de Apoio

Os scripts utilizados para geração de vetores de teste e validação estão em `hardware/sim/`:

| Script | Descrição |
|--------|-----------|
| `converteIMG.py` | Converte imagens PNG 28×28 para arquivos `.hex/.mif` compatíveis com o testbench |
| `converte.py` | Converte os pesos do modelo (`.txt`) para arquivos `.mif`/`.hex` para inicialização das ROMs |
| `golden_model.py` | Executa a inferência ELM em Python e retorna a predição esperada |

### Golden Model

O `golden_model.py` serve como referência para validação do RTL. Ele replica 
exatamente a lógica de ativação implementada no Verilog — incluindo a aproximação 
PWL (piecewise linear) do sigmoid em ponto fixo Q4.12 — garantindo que qualquer 
divergência entre o resultado do hardware e o golden model indique um erro de 
implementação RTL, e não uma diferença de algoritmo.

### Fluxo de Validação

**1. Converter a imagem de teste:**
```bash
python3 converteIMG.py
```

**2. Gerar os arquivos de pesos:**
```bash
python3 converte.py
```

**3. Obter a predição esperada:**
```bash
python3 golden_model.py
```

**4. Executar a simulação RTL:**
```bash
iverilog -o sim.out testbench.v elm_accel.v
vvp sim.out
```

**5. Comparar** o resultado da simulação com a saída do golden model.

## 9. Análise dos Resultados

A validação do co-processador foi realizada comparando a predição gerada pelo
hardware simulado (via testbench `elm_accel_tb.v`) com a saída do `golden_model.py`,
que replica a mesma lógica de ativação PWL em ponto fixo Q4.12 implementada no RTL.

Os resultados demonstram comportamento satisfatório para a grande maioria dos vetores
de teste: o hardware produz a mesma predição que o golden model, confirmando a
corretude da implementação do datapath MAC, da ativação aproximada e do argmax.

### Comportamento em Imagens Ambíguas

Foi observado que para imagens com características visuais menos definidas — como
dígitos escritos de forma irregular, com ruído ou traços pouco nítidos — o co-processador
pode retornar uma predição incorreta. Esse comportamento, no entanto, **não representa
uma falha de implementação RTL**: a mesma imagem submetida ao `golden_model.py`
produz o mesmo resultado divergente, indicando que a limitação é inerente ao modelo
ELM e à aproximação da função de ativação em ponto fixo, e não a um erro de hardware.

Esse alinhamento entre hardware e golden model é o critério central de validação do
Marco 1: o co-processador é considerado correto quando sua saída coincide com a do
golden model para todos os vetores de teste fornecidos, independentemente de o modelo
acertar ou não o dígito real da imagem.

### Métricas

| Métrica | Valor |
|---|---|
| Acurácia nos vetores de teste | A preencher |
| Ciclos médios por inferência | 610.580 |
| Frequência máxima de operação | 12,2ms por inferência |
