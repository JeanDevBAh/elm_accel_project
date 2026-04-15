# Marco 1 — Co-processador ELM em FPGA

## 1. Levantamento de Requisitos

### E/S
- Receber imagem 28×28 pixels (784 bytes, 8 bits/pixel, escala de cinza)
- Calcular camada oculta: `h = sigmoid(W_in · x + b)`, com 128 neurônios
- Calcular camada de saída: `y = β · h`, com 10 classes
- Retornar a predição via `pred = argmax(y)` → inteiro 0..9
- Sinalizar `busy`, `done` e `error` ao controlador externo
- Expor contador de ciclos (`cycles`) para medição de desempenho

### Estrutura
Implementar inferência ELM com pesos fornecidos, a arquitetura deve sequencial. Deve haver:
- FSM de controle
- datapath MAC (multiplica-acumula)
- ativação aproximada (LUT ou piecewise linear)
- argmax final
- memórias para armazenamento dos dados
- banco de registradores
- Valores devem ser representados em ponto fixo (fix-point) no formato Q4.12.
- Pesos podem residir em ROM inicializada (MIF/HEX) ou blocos RAM/ROM inferidos
- Deve haver uma estratégia clara para armazenamento e acesso a W_in, b, β

---

## 2. Ambiente de Desenvolvimento

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



### Mapa de Registradores (MMIO — Marco 2)

> Mapa preliminar para referência. A interface MMIO será implementada no Marco 2.

## 3. Mapa de Registradores (Preliminar)

A comunicação via MMIO (Memory-Mapped I/O) utiliza os seguintes endereços para controle pelo processador ARM:

| Endereço Relativo | Nome | Acesso | Descrição |
|:---|:---|:---|:---|
| **0x00** | `REG_CTRL` | R/W | Controle: Opcode, endereço manual e bit START. |
| **0x04** | `REG_STATUS` | R | Status: Bits BUSY, DONE, ERROR e resultado da Predição. |
| **0x08** | `REG_ADDR` | R/W | Endereço estendido para escrita em memórias internas. |
| **0x0C** | `REG_WDATA` | R/W | Porta de dados para alimentação de pesos e pixels. |
| **0x14** | `REG_CYCLES` | R | Contador de ciclos de clock para métricas de latência. |

---




## 4. Diagrama de Blocos

O diagrama de blocos do datapath e da FSM está disponível em [`docs/diagrama_blocos.svg`](hardware/docs/Datapah+FSM.drawio.svg).

![Diagrama de Blocos](hardware/docs/Datapah+FSM.drawio.svg)



## 5. Instalação e Configuração do Ambiente

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

## 6. Uso de Recursos FPGA

> Tabela a ser preenchida após síntese no Quartus Prime.

| Recurso | Utilizado | Disponível (Cyclone V) | % |
|---------|-----------|------------------------|---|
| LUTs | 1451 | 32.070 | ~4,5% |
| Flip-Flops | 2576 | 64.140 | ~4.0% |
| DSP Blocks | 2 | 87 | ~2.3% |
| M10K (BRAM) | 202 | 397 | ~50.8% |

---
## 7. Testes e Validação

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

## 8. Análise dos Resultados

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
