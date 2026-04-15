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
-FSM de controle
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

## 4. Mapa de Registradores (Preliminar)

A comunicação via MMIO (Memory-Mapped I/O) utiliza os seguintes endereços para controle pelo processador ARM[cite: 46, 90]:

| Endereço Relativo | Nome | Acesso | Descrição |
|:---|:---|:---|:---|
| **0x00** | `REG_CTRL` | R/W | Controle: Opcode, endereço manual e bit START. |
| **0x04** | `REG_STATUS` | R | Status: Bits BUSY, DONE, ERROR e resultado da Predição. |
| **0x08** | `REG_ADDR` | R/W | Endereço estendido para escrita em memórias internas. |
| **0x0C** | `REG_WDATA` | R/W | Porta de dados para alimentação de pesos e pixels. |
| **0x14** | `REG_CYCLES` | R | Contador de ciclos de clock para métricas de latência. |

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
### 5.4 Síntese com Quartus

Abrir o projeto em `marco1/quartus/elm_accel.qpf` no Quartus Prime e executar compilação completa (Processing → Start Compilation).

---


## 7. Uso de Recursos FPGA

> Tabela a ser preenchida após síntese no Quartus Prime.

| Recurso | Utilizado | Disponível (Cyclone V) | % |
|---------|-----------|------------------------|---|
| LUTs | 1451 | 32.070 | ~4,5% |
| Flip-Flops | 2576 | 64.140 | ~4.0% |
| DSP Blocks | 2 | 87 | ~2.3% |
| M10K (BRAM) | 202 | 397 | ~50.8% |

---

## 8. Análise dos Resultados

> A ser preenchida após execução dos testes de simulação.

- Acurácia nos vetores de teste:
- Ciclos médios por inferência:
- Frequência máxima de operação:
- Observações sobre divergências em relação ao golden model:
