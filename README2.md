# Marco 2 - Driver (Linux ARM - Assembly + C)

Disciplina: TEC 499 — MI Sistemas Digitais

Instituição: Universidade Estadual de Feira de Santana (UEFS)

Integrantes: Thiago Reis, Tairone Lima, Jean Carlos

Tutor: Wild Freitas

## Sumário

- [Visão Geral e Levantamento de Requisitos](#visão-geral-e-levantamento-de-requisitos)
- [Arquitetura do Sistema](#arquitetura-do-sistema)
- [Co-processador (FPGA)](#co-processador-fpga)
  - [Máquina de Estados (FSM)](#máquina-de-estados-fsm)
  - [Conjunto de Instruções (ISA)](#conjunto-de-instruções-isa)
  - [Formato dos Pacotes de 32 bits](#formato-dos-pacotes-de-32-bits)
  - [Memórias Internas](#memórias-internas)
  - [Registrador de Saída (`data_out`)](#registrador-de-saída-data_out)
  - [Módulo Top-Level e Integração HPS-FPGA](#módulo-top-level-e-integração-hps-fpga)
- [Driver em Assembly ARMv7](#driver-em-assembly-armv7)
  - [Mapeamento de Memória](#mapeamento-de-memória)
  - [Protocolo de Comunicação](#protocolo-de-comunicação)
  - [Funções Implementadas](#funções-implementadas)
- [API em C](#api-em-c)
- [Interface de Teste (`interface.c`)](#interface-de-teste-interfacec)
- [Estrutura de Arquivos (Abstração para Fins Didáticos)](#estrutura-de-arquivos-abstração-para-fins-didáticos)
- [Como Compilar e Executar](#como-compilar-e-executar)
- [Resultados Alcançados](#resultados-alcançados)
- [Referências](#referências)

---

## Visão Geral e Levantamento de Requisitos

Neste marco, o problema central consiste na integração do IP ao HPS (Hard Processor System). O desafio é estabelecer e validar a comunicação via Memory-Mapped I/O (MMIO) construindo um driver Linux com rotinas críticas em Assembly ARM. A solução deve ser capaz de inicializar o hardware, carregar os parâmetros da rede (pesos e bias), enviar uma imagem e gerenciar a inferência através de polling. Para atestar a estabilidade da conexão, a aplicação deve demonstrar o envio de uma imagem fixa e obter a classificação correta de forma estável e repetida, com métricas e resultados.

O Marco 02 exige a integração HW/Linux via Driver em Assembly para controle via MMIO, devendo permitir à aplicação:

- Inicializar o hardware.
- Enviar a imagem, os pesos e o bias para a FPGA.
- Iniciar a inferência.
- Aguardar a finalização através de *polling* (ou interrupção).
- Ler os resultados e as métricas.
- Garantir a estabilidade da comunicação (enviar 1 imagem fixa e obter classificação correta repetidamente).

Além disso, o enunciado exige para o repositório do Marco 02:

- Projeto Quartus integrando HPS e FPGA (bridges) com o IP mapeado.
- Driver Linux com rotinas críticas em Assembly ARM e API definida.
- Código Assembly comentado.
- Scripts para automação dos testes.
- READ.ME com detalhamento da solução, ambiente, testes e análise dos resultados.
  
---

## Arquitetura do Sistema

O sistema é dividido em três camadas bem definidas e essenciais para o funcionamento correto do projeto:

```
┌──────────────────────────────────────────────────────────────┐
│                     DE1-SoC (Cyclone V SoC)                  │
│                                                              │
│   ┌──────────────────────┐     ┌──────────────────────────┐  │
│   │         HPS          │     │           FPGA           │  │
│   │                      │     │                          │  │
│   │  ┌────────────────┐  │     │  ┌────────────────────┐  │  │
│   │  │  interface.c   │  │     │  │    CoProcessor     │  │  │
│   │  │       (C)      │  │     │  │    (FSM Geral)     │  │  │
│   │  └───────┬────────┘  │     │  └────────┬───────────┘  │  │
│   │          │           │     │           │              │  │
│   │  ┌───────▼────────┐  │     │  ┌────────▼───────────┐  │  │
│   │  │DriverAcelerador│  │     │  │    neural_unit     │  │  │
│   │  │   (Assembly)   │  │     │  │    (Inferência)    │  │  │
│   │  └───────┬────────┘  │     │  └────────┬───────────┘  │  │
│   │          │  MMAP     │     │           │              │  │
│   └──────────┼───────────┘     └───────────┼──────────────┘  │
│              │                             │                 │
│              └─────────── PIO Bridges ─────┘                 │
│                  (data_in / data_out / signals)              │
└──────────────────────────────────────────────────────────────┘
```

A comunicação entre HPS e FPGA é realizada por **três registradores PIO (Parallel I/O)** configurados via Platform Designer (Qsys), mapeados na região de endereçamento de periféricos da FPGA (`0xFF200000`):

| Registrador  | Offset  | Largura | Direção     | Função                                      |
|:-------------|:-------:|:-------:|:-----------:|:--------------------------------------------|
| `signals`    | `0x10`  | 3 bits  | HPS → FPGA  | Controle: `enable[0]`, `clr[1]`, `rst[2]`  |
| `data_in`    | `0x30`  | 32 bits | HPS → FPGA  | Pacote de instrução/dado                   |
| `data_out`   | `0x20`  | 32 bits | FPGA → HPS  | Resultado, flags de status, contador        |

---

## Co-processador (FPGA)

O módulo `CoProcessor` é o núcleo do acelerador. Ele recebe instruções de 32 bits pelo barramento `data_in`, executa operações de escrita em memórias internas e, quando acionado, atribui a inferência ao submódulo `neural_unit`, dentre outras funções.

### Máquina de Estados (FSM)

A máquina de estados do `CoProcessor` controla o recebimento das instruções enviadas pelo HPS, a escrita dos dados nas memórias internas e o início da inferência na unidade neural. Ela também é responsável por manter as flags de controle, como `busy`, `done` e `error`, além de contabilizar os ciclos de clock gastos durante a inferência.

## Máquina de Estados do CoProcessor

```text
 RST
  |
  v
+---------+
| ST_IDLE |
+---------+
     |
     | ENABLE && !BUSY
     v
+-----------+
| ST_DECODE |
+-----------+
   |     |       |
   |     |       +----------------+
   |     |                        |
   |     v                        v
   |   START             INSTRUÇÃO INVÁLIDA
   |     |                        |
   |     v                        v
   | +--------------+        +--------+
   | | ST_INFERENCE |        |  ERRO  |
   | +--------------+        +--------+
   |        |
   |        | DONE
   |        v
   |   +---------+
   |   | ST_IDLE |
   |   +---------+
   |
   | ESCRITA
   v
+-----------+
| ST_MEMORY |
+-----------+
     |
     | DONE
     v
+---------+
| ST_IDLE |
+---------+
```

### Estados da Máquina

| Estado | Função |
|---|---|
| `ST_IDLE` | Estado inicial e de espera. Aguarda o pulso do sinal `enable` para capturar uma nova instrução. Uma nova instrução só é aceita quando o co-processador não está ocupado, evitando sobrescrita ou captura incorreta de dados. |
| `ST_DECODE` | Decodifica a instrução recebida pelo barramento `data_in`. O opcode é obtido pelos bits menos significativos da palavra de entrada, em `data_in[2:0]`. Neste estado também ocorre a validação dos endereços usados nas operações de escrita. Caso um endereço ultrapasse o limite da memória correspondente ou a instrução seja inválida, a flag `error` é ativada. |
| `ST_MEMORY` | Executa operações de escrita nas memórias internas do co-processador, como memória de imagem, pesos, bias e beta. O estado só é finalizado quando a escrita é confirmada, garantindo que o dado foi armazenado corretamente antes do retorno ao estado de espera. |
| `ST_INFERENCE` | Inicia e controla a execução da inferência. Neste estado, o controle dos barramentos de memória é entregue à `neural_unit`, que passa a acessar os dados carregados previamente. O contador de ciclos é incrementado a cada clock enquanto a inferência estiver em execução. A máquina só retorna para `ST_IDLE` quando o sinal `inference_done` é ativado. |


### Conjunto de Instruções (ISA)

O co-processador possui um conjunto de 8 instruções, codificadas nos bits `[2:0]` do pacote de 32 bits:

| Código | Mnemônico             | Descrição                                                         |
|:------:|:----------------------|:------------------------------------------------------------------|
| `000`  | `STORE_IMG`           | Grava um pixel (8 bits) na memória de imagem                     |
| `001`  | `STORE_WEIGHTS_ADDR`  | Define o endereço na memória de pesos para a próxima escrita     |
| `010`  | `STORE_WEIGHTS_VALUE` | Grava o valor (16 bits) no endereço de pesos previamente setado  |
| `011`  | `STORE_BIAS`          | Grava um valor de bias (16 bits) na memória de bias              |
| `100`  | `STORE_BETA`          | Grava um valor de beta (16 bits) na memória de beta              |
| `101`  | `START`               | Dispara a inferência neural e transiciona para ST_INFERENCE       |
| `110`  | `STATUS`              | Leitura de status                                                |
| `111`  | `NOP`                 | Nenhuma operação                                                 |

> **Nota sobre pesos:** A gravação de um peso requer duas instruções consecutivas, o primeiro `STORE_WEIGHTS_ADDR` (que apenas armazena o endereço e volta ao idle), depois `STORE_WEIGHTS_VALUE` (que realmente grava o valor naquele endereço). Isso permite endereços de até 17 bits (100.352 entradas) sem comprometer o espaço do valor de 16 bits dentro de um único pacote de 32 bits.

### Formato dos Pacotes de 32 bits

Cada instrução é codificada em um único pacote de 32 bits enviado ao registrador `data_in`. O layout dos campos varia por instrução:

**STORE_IMG (`000`)**
```
  Bit:  31       21  20     13  12      3   2    0
        ┌──────────┬──────────┬──────────┬────────┐
        │ (não uso)│  pixel   │  endereço│  0 0 0 │
        │          │  [7:0]   │  [9:0]   │        │
        └──────────┴──────────┴──────────┴────────┘
```

**STORE_BIAS (`011`)**
```
  Bit:  31   26  25          10   9       3   2    0
        ┌──────┬──────────────┬────────────┬────────┐
        │(n/u) │  bias [15:0] │ endereço   │  0 1 1 │
        │      │              │  [6:0]     │        │
        └──────┴──────────────┴────────────┴────────┘
```

**STORE_BETA (`100`)**
```
  Bit:  31  30  29          14   13       3   2    0
        ┌────┬──────────────────┬──────────┬────────┐
        │(n/u│  beta [15:0]     │ endereço │  1 0 0 │
        │    │                  │  [10:0]  │        │
        └────┴──────────────────┴──────────┴────────┘
```

**STORE_WEIGHTS_ADDR (`001`)**
```
  Bit:  31   20  19                3   2    0
        ┌──────┬────────────────────┬────────┐
        │(n/u) │  endereço [16:0]   │  0 0 1 │
        └──────┴────────────────────┴────────┘
```

**STORE_WEIGHTS_VALUE (`010`)**
```
  Bit:  31   19  18                3   2    0
        ┌──────┬────────────────────┬────────┐
        │(n/u) │  peso [15:0]       │  0 1 0 │
        └──────┴────────────────────┴────────┘
```

**START (`101`)**, **STATUS (`110`)** e **NOP (`111`)** seguem o mesmo formato, onde os 29 bits restantes são ignorados pelo co-processador:
```
  Bit:  31                          3   2    0
        ┌────────────────────────────┬────────┐
        │         (ignorado)         │ opcode │
        └────────────────────────────┴────────┘
```

### Memórias Internas

Cada tipo de dado possui sua própria memória on-chip, instanciada como `lsu_controller` parametrizado para o dispositivo Cyclone V com tipo `AUTO` (o compilador Quartus seleciona entre M10K e MLAB). Todas operam com 3 ciclos de latência por operação.

| Memória  | Tamanho       | Largura | Capacidade Total | Conteúdo                                   |
|:---------|:-------------:|:-------:|:----------------:|:-------------------------------------------|
| `mem_img`    | 784 posições  | 8 bits  | ~784 B           | Pixels da imagem de entrada (28×28)        |
| `mem_bias`   | 128 posições  | 16 bits | ~256 B           | Vieses da camada oculta (128 neurônios)    |
| `mem_beta`   | 1.280 posições| 16 bits | ~2,5 KB          | Parâmetros beta da camada de saída (128×10)|
| `mem_weight` | 100.352 posições | 16 bits | ~196 KB       | Pesos W_in da camada de entrada (784×128)  |

Durante a inferência, o multiplexador de barramento transfere o controle de todos os sinais de enable e endereço das memórias para a `neural_unit`, que passa a ditar quais endereços ler em qual ordem.

### Registrador de Saída (`data_out`)

O HPS lê o resultado completo num único acesso ao registrador `data_out` de 32 bits:

```
  Bit:  31                    8   7    6      5       4      3    0
        ┌────────────────────────┬──┬──────┬──────┬───────┬──────────┐
        │  contador_ciclos[23:0] │0 │ erro │ busy │  done │  dígito  │
        │                        │  │      │      │       │  [3:0]   │
        └────────────────────────┴──┴──────┴──────┴───────┴──────────┘
```

| Campo              | Bits     | Descrição                                                   |
|:-------------------|:--------:|:------------------------------------------------------------|
| `dígito`           | `[3:0]`  | Dígito predito pela rede (0–9)                              |
| `fl_processor_done`| `[4]`    | Operação concluída com sucesso                              |
| `fl_processor_busy`| `[5]`    | Co-processador ocupado (aguardando conclusão)               |
| `fl_error`         | `[6]`    | Endereço inválido ou instrução desconhecida                 |
| *(reservado)*      | `[7]`    | Sempre 0                                                    |
| `contador_ciclos`  | `[31:8]` | Número de ciclos de clock consumidos pela inferência (24 bits) |

### Módulo Top-Level e Integração HPS-FPGA

O módulo `ghrd_top` integra todos os componentes da plataforma DE1-SoC. O co-processador é conectado diretamente ao clock de 50 MHz do sistema (`CLOCK_50`) e recebe seus três sinais de controle através do registrador PIO `signals`, gerenciado pelo subsistema `soc_system` (Platform Designer):

```verilog
CoProcessor u_cop (
    .clk           ( CLOCK_50   ),
    .rst           ( signals[2] ),
    .clr_operation ( signals[1] ),
    .enable        ( signals[0] ),
    .data_in       ( data_in    ),
    .data_out      ( data_out   )
);
```

O sinal de reset do co-processador (`signals[2]`) é independente do mecanismo de reset do HPS (`hps_fpga_reset_n`), permitindo que o "software" reinicialize o acelerador a qualquer momento sem afetar o restante do sistema.

---

## Driver em Assembly ARMv7

O arquivo `DriverAcelerador.s` implementa todas as funções de comunicação com o co-processador diretamente em Assembly ARMv7.

### Mapeamento de Memória

O acesso aos registradores PIO da FPGA é feito via `/dev/mem` e a chamada de sistema `mmap2`, que mapeia a página física `0xFF200000` no espaço de endereçamento virtual do processo em execução no HPS.

```
Endereço Físico Base (FPGA PIOs leves): 0xFF200000
Page offset para mmap2:                0xFF200  (endereço / 4096)
Tamanho do mapeamento:                 4096 bytes (1 página)
Permissões:                            PROT_READ | PROT_WRITE (flag 3)
Tipo de mapeamento:                    MAP_SHARED (flag 1)
```

A função `inicializar_hardware` retorna o ponteiro virtual resultante em `R0`, que é então passado como primeiro argumento (`base`) para todas as demais funções.

### Protocolo de Comunicação

Toda transação entre HPS e co-processador segue um protocolo de três fases:

```
1. ESCRITA:   STR R6, [R0, #OFFSET_DATA_IN]    → deposita o pacote no registrador data_in
2. PULSO:     BL pulsar_enable                 → sinaliza nova instrução (enable=1, depois 0)
3. POLLING:   BL loop_polling                  → aguarda done=1 ou error=1 em data_out
              BL clear_fpga                    → limpa os flags (clr=1, depois 0)
```

Dois mecanismos de espera são usados conforme o contexto:

- **`loop_polling`**: Lê `data_out` ciclicamente e retorna quando `fl_done` ou `fl_error` estiver setado. Usado após operações que produzem resultado (escrita em memória, inferência).
- **`aguardar_idle`**: Aguarda o bit `fl_busy` ser zerado. Usado entre as duas instruções de envio de peso (`STORE_WEIGHTS_ADDR` → `STORE_WEIGHTS_VALUE`), onde o primeiro pacote não gera `done` — apenas registra o endereço e retorna ao idle.

### Funções Implementadas

#### `inicializar_hardware` → `volatile uint32_t*`
Abre `/dev/mem` via syscall `open`, em seguida chama `mmap2` para mapear a página física da FPGA. Retorna o ponteiro virtual em `R0`.

#### `resetar_fpga(base)`
Escreve `BIT_RESET` (bit 2 de `signals`) e em seguida escreve zero, gerando um pulso de reset síncrono. Reinicializa completamente a FSM e todos os registradores internos do co-processador.

#### `clear_fpga(base)`
Pulsa `BIT_CLEAR` (bit 1 de `signals`). Limpa os flags `fl_processor_done` e `fl_error` sem afetar os dados nas memórias internas, preparando o co-processador para aceitar a próxima instrução.

#### `enviarImagem(base, buffer)`
Itera sobre os 784 pixels do buffer de entrada (`uint8_t[784]`). Para cada pixel, monta o pacote `STORE_IMG` com o endereço (iterador) nos bits `[12:3]` e o valor do pixel nos bits `[20:13]`, envia, espera o `done` e limpa o flag.

```
pacote = (endereco << 3) | (pixel << 13) | 0b000
```

#### `enviarBias(base, buffer)`
Itera sobre 128 valores de bias (`int16_t[128]`). Monta o pacote `STORE_BIAS` com o endereço nos bits `[9:3]` e o valor de 16 bits nos bits `[25:10]`.

```
pacote = 0b011 | (endereco << 3) | (bias << 10)
```

#### `enviarBeta(base, buffer)`
Itera sobre 1.280 valores beta (`int16_t[1280]`). Monta o pacote `STORE_BETA` com o endereço nos bits `[13:3]` e o valor nos bits `[29:14]`.

```
pacote = 0b100 | (endereco << 3) | (beta << 14)
```

#### `enviarPesos(base, buffer)`
Itera sobre 100.352 pesos (`int16_t[100352]`). Para cada peso, são enviadas **duas instruções consecutivas**:

1. **Pacote de endereço** (`STORE_WEIGHTS_ADDR`): `0b001 | (endereco << 3)` — espera apenas `aguardar_idle`.
2. **Pacote de valor** (`STORE_WEIGHTS_VALUE`): `0b010 | (peso << 3)` — espera `loop_polling` e limpa.

Essa separação é necessária porque o endereço de 17 bits não caberia junto com o valor de 16 bits em um único pacote de 32 bits sem que houvesse sobreposição de campos.

#### `iniciar_inferencia(base)` → `int`
Envia o pacote `START` (`0b101`), pulsa enable e bloqueia em `loop_polling` até `fl_done`. Retorna o conteúdo completo de `data_out` diretamente para o C, que extrai o dígito, as flags e o contador de ciclos por deslocamentos de bits.

---

## API em C

O arquivo `APIdriverFPGA.h` declara os protótipos das funções Assembly, tornando-as acessíveis a qualquer programa C compilado junto com o objeto Assembly:

```c
volatile uint32_t* inicializar_hardware(void);
void enviarImagem   (volatile uint32_t *base, const uint8_t  *buffer);
void enviarPesos    (volatile uint32_t *base, const uint16_t *buffer);
void enviarBias     (volatile uint32_t *base, const uint16_t *buffer);
void enviarBeta     (volatile uint32_t *base, const uint16_t *buffer);
int  iniciar_inferencia(volatile uint32_t *base);
void resetar_fpga   (volatile uint32_t *base);
void clear_fpga     (volatile uint32_t *base);
```

O uso de `volatile uint32_t*` é essencial: garante que o compilador C não otimize (em cache ou reordene) os acessos a esses endereços, que correspondem a registradores de hardware com efeitos colaterais imediatos.

---

## Interface de Teste (`interface.c`)

O arquivo `interface.c` demonstra o fluxo completo de utilização do acelerador:

```
inicializar_hardware()
        │
        ▼
resetar_fpga()          ← estado limpo e conhecido
        │
        ▼
enviarBias()            ← 128 valores × 16 bits
enviarBeta()            ← 1.280 valores × 16 bits
enviarPesos()           ← 100.352 valores × 16 bits
        │
        ▼ (loop de testes)
enviarImagem()          ← 784 pixels × 8 bits
        │
        ▼
iniciar_inferencia()    ← retorna data_out compactado
        │
        ▼
Extração dos campos:
  resultado      = retorno & 0x0F
  done           = (retorno >> 4) & 1
  busy           = (retorno >> 5) & 1
  erro           = (retorno >> 6) & 1
  contador_clock = (retorno >> 8) & 0xFFFFFF
```

Os pesos, biases e betas são carregados apenas **uma vez** antes do loop de inferências, refletindo o comportamento real de um sistema embarcado: os parâmetros da rede são fixos e permanecem nas memórias do co-processador durante toda a sessão. Apenas a imagem de entrada é substituída a cada nova inferência.

---

## Estrutura de Arquivos (Abstração para Fins Didáticos)

```
.
├── hardware/
│   ├── ghrd_top.v            # Módulo top-level da DE1-SoC; integra HPS e co-processador
│   └── CoProcessor.v         # Co-processador neural: FSM, memórias, neural_unit
│
├── "software"/
│   ├── DriverAcelerador.s    # Driver de baixo nível em Assembly ARMv7
│   ├── APIdriverFPGA.h       # Declarações C das funções Assembly
│   ├── interface.c           # Programa principal de teste
│   ├── pesos.h               # Pesos, biases e betas da rede neural (vetores C)
│   └── dados_imagem.h        # Imagens de teste do MNIST (dígitos 4, 7, 8, 9)
```

---

## Como Compilar e Executar

### Pré-requisitos

- Acesso SSH à DE1-SoC com Linux rodando no HPS.
- Bitstream da FPGA já gravado com o Platform Designer configurado (PIOs `data_in`, `data_out`, `signals` no endereço `0xFF200000`).
- `gcc` disponível nativamente na placa.

### Compilação e Execução (diretamente na DE1-SoC)

Conecte-se à placa via SSH e eleve seus privilégios através do `sudo su`:

```bash
ssh <usuario>@<IP_DA_PLACA>
sudo su
```

Compile e execute:

```bash
gcc DriverAcelerador.s interface.c -o driver
./driver
```

### Saída Esperada

```
Resetando hardware...
Enviando Bias...
Enviando Betas...
Enviando W_in...

--- Iniciando Execução 0 ---
Enviando imagem...
Iniciando inferência...
 | Resultado: 4
 | Erro: 0
 | Ciclos de clock: XXXX
 | Done: 1
```
### Linguagens

| Linguagem | Uso |
|:----------|:----|
| **Verilog** | Descrição do co-processador e módulo top-level em HDL |
| **Assembly ARMv7** | Driver de baixo nível para comunicação com a FPGA |
| **C** | Interface de teste e API do driver |

### Software
| Ferramenta | Uso |
|:---|:---|
| **Intel Quartus Prime 21.1 Lite** | Síntese, place-and-route e análise de recursos. |
| **GCC (ARM nativo)** | Compilação do driver Assembly e da interface C diretamente na DE1-SoC. |
| **OpenSSH** | Acesso remoto à placa para transferência de arquivos, compilação e execução. |

### Hardware

| Componente | Descrição |
|:-----------|:----------|
| **DE1-SoC** | Placa com FPGA Cyclone V (5CSEMA5F31C6) + ARM Cortex-A9 (HPS) |

## Resultados Alcançados

### Correção da Classificação

O acelerador foi validado com quatro amostras do dataset MNIST disponíveis em `dados_imagem.h`, representando os dígitos **4**, **7**, **8** e **9** como vetores `uint8_t[784]` de pixels em escala de cinza (0–255). Para cada imagem, o campo `resultado` de `data_out[3:0]` deve retornar exatamente o dígito correspondente, e o flag `fl_error` deve permanecer em zero, confirmando que nenhum endereço inválido foi gerado durante o carregamento.

O programa de teste em `interface.c`, na configuração atual, executa a inferência sobre `imagem4` e imprime o resultado diretamente no terminal via SSH. A estrutura de loop permite ampliar facilmente o número de inferências e alternar entre as imagens disponíveis.

### Desempenho e Contador de Ciclos

O co-processador opera a **50 MHz** (período de clock de 20 ns), e o campo `contador_ciclos` de 24 bits em `data_out[31:8]` registra com precisão de um ciclo o tempo decorrido exclusivamente durante a fase de inferência do momento em que a `neural_unit` é ativada até o sinal `inference_done`.
Para contextualizar a escala do problema computacional resolvido em hardware:

| Etapa                        | Operações envolvidas                          |
|:-----------------------------|:----------------------------------------------|
| Carregamento da imagem       | 784 escritas de 8 bits                        |
| Carregamento dos pesos W_in  | 100.352 escritas de 16 bits (2 pacotes cada)  |
| Carregamento do bias         | 128 escritas de 16 bits                       |
| Carregamento do beta         | 1.280 escritas de 16 bits                     |

O carregamento dos parâmetros (pesos, bias, beta) é realizado **uma única vez** por sessão e a partir da segunda inferência em diante, o ciclo se reduz ao envio da imagem (784 pacotes) seguido da execução em hardware, tornando o sistema altamente eficiente para cenários de inferência repetida.

### Flags de Status

| Flag           | Valor esperado | Significado                                                        |
|:---------------|:--------------:|:-------------------------------------------------------------------|
| `fl_done`      | `1`            | Operação concluída com sucesso                                     |
| `fl_error`     | `0`            | Nenhum endereço inválido detectado durante o carregamento          |
| `fl_busy`      | `0`            | Co-processador liberado ao término (retornou a ST_IDLE)            |

Caso `fl_error` seja `1`, a causa mais provável é um índice fora dos limites em uma das funções de envio, por exemplo, tentar escrever além das 784 posições da memória de imagem ou além das 128 posições de bias. A FSM cancela a operação e retorna ao idle sem corromper os dados já gravados.


## Referências

PATTERSON, David A.; HENNESSY, John L. Computer Organization and Design: The Hardware/Software Interface. ARM® Edition. San Francisco: Morgan Kaufmann, 2016.

---
