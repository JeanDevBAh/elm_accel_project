# Marco 1 — Co-processador ELM em FPGA

## 1. Levantamento de Requisitos

### E/S
- Receber imagem 28×28 pixels (784 bytes, 8 bits/pixel, escala de cinza)
- Calcular camada oculta: `h = sigmoid(W_in · x + b)`, com 128 neurônios
- Calcular camada de saída: `y = β · h`, com 10 classes
- Retornar a predição via `pred = argmax(y)` → inteiro 0..9
- Sinalizar `busy`, `done` e `error` ao controlador externo
- Expor contador de ciclos (`cycles`) para medição de desempenho

### Estrurtura
Implementar inferência ELM com pesos fornecidos.
● A arquitetura deve sequencial
● Deve haver:
○ FSM de controle
○ datapath MAC (multiplica-acumula)
○ ativação aproximada (LUT ou piecewise linear)
○ argmax final
○ memórias para armazenamento dos dados
○ banco de registradores
● Valores devem ser representados em ponto fixo (fix-point) no formato Q4.12.
● Pesos podem residir em ROM inicializada (MIF/HEX) ou blocos RAM/ROM inferidos
● Deve haver uma estratégia clara para armazenamento e acesso a W_in, b, β

---

## 2. Ambiente de Desenvolvimento

### Software

| Ferramenta | Versão | Uso |
|------------|--------|-----|
| Intel Quartus Prime | 21.1 Lite | Síntese e place-and-route |
| ModelSim-Intel | 2021.1 | Simulação RTL |
| Python | 3.10+ | Scripts de geração de vetores e golden model |
| NumPy | 1.24+ | Cálculo do golden model |

### Hardware

| Componente | Descrição |
|------------|-----------|
| DE1-SoC | Placa com Cyclone V (5CSEMA5F31C6) + ARM Cortex-A9 |
| USB-Blaster | Programação da FPGA via JTAG |

---

## 3. Arquitetura do Co-processador

### Diagrama de Blocos

```
                         ┌─────────────────────────────────────────┐
                         │              elm_accel                   │
                         │                                          │
  img_we ──────────────► │  ┌──────────┐    ┌───────────────────┐  │
  img_addr ─────────────►│  │ img_ram  │    │   FSM de controle │  │
  img_wdata ────────────►│  │ (784x8b) │    │   (24 estados)    │  │
                         │  └────┬─────┘    └────────┬──────────┘  │
                         │       │                   │             │
                         │  ┌────▼─────┐    ┌────────▼──────────┐  │
  start ────────────────►│  │w_in_ram  │    │     mac_q412      │  │
                         │  │(100352x16│    │  (multiplicador   │  │
  busy ◄─────────────────│  │   bits)  │    │   Q4.12)          │  │
  done ◄─────────────────│  └──────────┘    └────────┬──────────┘  │
  error ◄────────────────│                           │             │
  pred[3:0] ◄────────────│  ┌──────────┐    ┌────────▼──────────┐  │
  cycles[31:0] ◄─────────│  │  b_ram   │    │  sigmoid_pwl      │  │
                         │  │ (128x16b)│    │  (ativação PWL)   │  │
                         │  └──────────┘    └───────────────────┘  │
                         │                                          │
                         │  ┌──────────┐    ┌───────────────────┐  │
                         │  │ beta_ram │    │  argmax (lógica   │  │
                         │  │(1280x16b)│    │  sequencial)      │  │
                         │  └──────────┘    └───────────────────┘  │
                         └─────────────────────────────────────────┘
```

### Fluxo da FSM

```
IDLE → LOAD_BIAS_REQ → (W1→W4) → HID_REQ → (W1→W4) → HID_ACC
  ↑                                                        │
  │                                              (loop 784 pixels)
  │                                                        ▼
  │                                               ACTIVATION
  │                                          (loop 128 neurônios)
  │                                                        ▼
  │                                    OUT_INIT → BETA_REQ → (W1→W4)
  │                                                        │
  │                                              (loop 128 × 10)
  │                                                        ▼
  │                                    ARGMAX_INIT → ARGMAX_STEP
  │                                                        │
  └──────────────────────────── DONE ◄────────────────────┘
```

### Mapa de Registradores (MMIO — Marco 2)

> Mapa preliminar para referência. A interface MMIO será implementada no Marco 2.

| Offset | Nome | Acesso | Largura | Descrição |
|--------|------|--------|---------|-----------|
| `0x00` | CTRL | W | 32 bits | bit[0]=start |
| `0x04` | STATUS | R | 32 bits | bit[0]=busy, bit[1]=done, bit[2]=error, bits[6:3]=pred |
| `0x08` | IMG_ADDR | W | 32 bits | Endereço do pixel (0..783) |
| `0x0C` | IMG_DATA | W | 32 bits | Valor do pixel (0..255) |
| `0x10` | CYCLES | R | 32 bits | Ciclos gastos na última inferência |

---

## 4. Módulos RTL

### `elm_accel.v`
Módulo top do co-processador. Contém a FSM de controle com 24 estados, os contadores de iteração, os acumuladores Q4.12 e as instâncias de todas as RAMs e submódulos.

### `mac_q412.v`
Multiplicador de dois operandos Q4.12 de 16 bits. Produz resultado de 32 bits com ajuste de escala via shift aritmético de 12 bits, corrigindo a escala dupla gerada pela multiplicação.

### `sigmoid_pwl.v`
Aproximação linear por partes (PWL) da função sigmoide com 5 segmentos:

| Intervalo | Saída (real) |
|-----------|--------------|
| x ≤ −4 | 0 |
| −4 < x < −2 | 0.0625 × (x + 4) |
| −2 ≤ x < 2 | 0.5 + 0.125 × x |
| 2 ≤ x < 4 | 0.75 + 0.0625 × (x − 2) |
| x ≥ 4 | 1 |

---

## 5. Instalação e Configuração do Ambiente

### 5.1 Clonar o repositório

```bash
git clone https://github.com/<usuario>/elm-fpga-classifier.git
cd elm-fpga-classifier/marco1
```

### 5.2 Instalar dependências Python (golden model e geração de vetores)

```bash
pip install numpy pillow
```

### 5.3 Simulação com ModelSim

```bash
cd marco1/scripts
./run_sim.sh
```

O script compila todos os arquivos RTL e o testbench, executa a simulação e compara as saídas com o golden model Python.

### 5.4 Síntese com Quartus

Abrir o projeto em `marco1/quartus/elm_accel.qpf` no Quartus Prime e executar compilação completa (Processing → Start Compilation).

---

## 6. Testes de Funcionamento

### 6.1 Estrutura dos testes

```
marco1/
├── tb/
│   └── tb_elm_accel.v       # Testbench principal
├── scripts/
│   ├── run_sim.sh            # Executa simulação completa
│   ├── gen_vectors.py        # Gera vetores de teste a partir de imagens MNIST
│   └── golden_model.py       # Referência Python para comparação
└── sim/
    ├── vectors/              # Vetores de entrada gerados
    └── results/              # Saídas da simulação
```

### 6.2 Como executar

```bash
# Gerar vetores de teste
python3 scripts/gen_vectors.py --dataset mnist_test/ --n 10 --out sim/vectors/

# Executar simulação
./scripts/run_sim.sh

# Comparar com golden model
python3 scripts/golden_model.py --vectors sim/vectors/ --results sim/results/
```

### 6.3 Critério de aprovação

A simulação é considerada aprovada quando `pred` do RTL coincide com `pred` do golden model Python para todos os vetores de teste fornecidos.

---

## 7. Uso de Recursos FPGA

> Tabela a ser preenchida após síntese no Quartus Prime.

| Recurso | Utilizado | Disponível (Cyclone V) | % |
|---------|-----------|------------------------|---|
| LUTs | — | 32.070 | — |
| Flip-Flops | — | 64.140 | — |
| DSP Blocks | — | 87 | — |
| M10K (BRAM) | — | 397 | — |

---

## 8. Análise dos Resultados

> A ser preenchida após execução dos testes de simulação.

- Acurácia nos vetores de teste:
- Ciclos médios por inferência:
- Frequência máxima de operação:
- Observações sobre divergências em relação ao golden model:
