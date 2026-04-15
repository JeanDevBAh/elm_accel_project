// =============================================================================
// Testbench: elm_accel_tb.v
// Descrição: Valida a inferência do co-processador ELM contra o golden model.
//
// Fluxo:
//   1. Carrega imagem via img.hex         (gerado por converteIMG.py)
//   2. Carrega pesos W_in via w_in.hex    (gerado por converte.py)
//   3. Carrega bias b via b.hex           (gerado por converte.py)
//   4. Carrega beta via beta_q.hex        (gerado por converte.py)
//   5. Dispara START e aguarda DONE
//   6. Imprime pred — comparar manualmente com saída do golden_model.py
//
// Uso:
//   iverilog -o sim.out elm_accel_tb.v elm_accel.v
//   vvp sim.out
// =============================================================================

`timescale 1ns/1ps

module elm_accel_tb;

    // -------------------------------------------------------------------------
    // Parâmetros
    // -------------------------------------------------------------------------
    parameter CLK_PERIOD   = 20;   // 50 MHz → 20 ns
    parameter IMG_PIXELS   = 784;  // 28x28
    parameter W_IN_WORDS   = 100352; // 128 neurônios × 784 entradas
    parameter B_WORDS      = 128;
    parameter BETA_WORDS   = 1280; // 128 × 10 classes

    parameter TIMEOUT_CYCLES = 10_000_000;

    // -------------------------------------------------------------------------
    // Sinais do DUT (elm_accel)
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst;
    reg         start;
    reg         clear_status;

    reg         img_we;
    reg  [9:0]  img_addr;
    reg  [7:0]  img_wdata;

    reg         w_in_we;
    reg  [16:0] w_in_addr_ext;
    reg  [15:0] w_in_wdata;

    reg         b_we;
    reg  [6:0]  b_addr_ext;
    reg  [15:0] b_wdata;

    reg         beta_we;
    reg  [10:0] beta_addr_ext;
    reg  [15:0] beta_wdata;

    wire        busy;
    wire        done;
    wire        error;
    wire [3:0]  pred;
    wire [31:0] cycles;

    // -------------------------------------------------------------------------
    // Memórias temporárias para os dados lidos dos .hex
    // -------------------------------------------------------------------------
    reg [7:0]  img_mem   [0:IMG_PIXELS-1];
    reg [15:0] w_in_mem  [0:W_IN_WORDS-1];
    reg [15:0] b_mem     [0:B_WORDS-1];
    reg [15:0] beta_mem  [0:BETA_WORDS-1];

    integer i;
    integer timeout_cnt;

    // -------------------------------------------------------------------------
    // Instância do DUT
    // -------------------------------------------------------------------------
    elm_accel u_dut (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .clear_status  (clear_status),

        .img_we        (img_we),
        .img_addr      (img_addr),
        .img_wdata     (img_wdata),

        .w_in_we       (w_in_we),
        .w_in_addr_ext (w_in_addr_ext),
        .w_in_wdata    (w_in_wdata),

        .b_we          (b_we),
        .b_addr_ext    (b_addr_ext),
        .b_wdata       (b_wdata),

        .beta_we       (beta_we),
        .beta_addr_ext (beta_addr_ext),
        .beta_wdata    (beta_wdata),

        .busy          (busy),
        .done          (done),
        .error         (error),
        .pred          (pred),
        .cycles        (cycles)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Tarefa: Reset
    // -------------------------------------------------------------------------
    task do_reset;
        begin
            rst          <= 1'b1;
            start        <= 1'b0;
            clear_status <= 1'b0;
            img_we       <= 1'b0;
            w_in_we      <= 1'b0;
            b_we         <= 1'b0;
            beta_we      <= 1'b0;
            @(posedge clk);
            @(posedge clk);
            rst <= 1'b0;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Tarefa: Carregar imagem na RAM interna do DUT
    // -------------------------------------------------------------------------
    task load_image;
        integer j;
        begin
            $display("[TB] Carregando imagem (%0d pixels)...", IMG_PIXELS);
            for (j = 0; j < IMG_PIXELS; j = j + 1) begin
                @(posedge clk);
                img_we    <= 1'b1;
                img_addr  <= j[9:0];
                img_wdata <= img_mem[j];
            end
            @(posedge clk);
            img_we <= 1'b0;
            $display("[TB] Imagem carregada.");
        end
    endtask

    // -------------------------------------------------------------------------
    // Tarefa: Carregar W_in
    // -------------------------------------------------------------------------
    task load_w_in;
        integer j;
        begin
            $display("[TB] Carregando W_in (%0d palavras)...", W_IN_WORDS);
            for (j = 0; j < W_IN_WORDS; j = j + 1) begin
                @(posedge clk);
                w_in_we       <= 1'b1;
                w_in_addr_ext <= j[16:0];
                w_in_wdata    <= w_in_mem[j];
            end
            @(posedge clk);
            w_in_we <= 1'b0;
            $display("[TB] W_in carregado.");
        end
    endtask

    // -------------------------------------------------------------------------
    // Tarefa: Carregar bias b
    // -------------------------------------------------------------------------
    task load_b;
        integer j;
        begin
            $display("[TB] Carregando bias b (%0d palavras)...", B_WORDS);
            for (j = 0; j < B_WORDS; j = j + 1) begin
                @(posedge clk);
                b_we       <= 1'b1;
                b_addr_ext <= j[6:0];
                b_wdata    <= b_mem[j];
            end
            @(posedge clk);
            b_we <= 1'b0;
            $display("[TB] Bias b carregado.");
        end
    endtask

    // -------------------------------------------------------------------------
    // Tarefa: Carregar beta
    // -------------------------------------------------------------------------
    task load_beta;
        integer j;
        begin
            $display("[TB] Carregando beta (%0d palavras)...", BETA_WORDS);
            for (j = 0; j < BETA_WORDS; j = j + 1) begin
                @(posedge clk);
                beta_we       <= 1'b1;
                beta_addr_ext <= j[10:0];
                beta_wdata    <= beta_mem[j];
            end
            @(posedge clk);
            beta_we <= 1'b0;
            $display("[TB] Beta carregado.");
        end
    endtask

    // -------------------------------------------------------------------------
    // Tarefa: Disparar inferência e aguardar DONE com timeout
    // -------------------------------------------------------------------------
    task run_inference;
        begin
            $display("[TB] Disparando START...");
            @(posedge clk);
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;

            timeout_cnt = 0;
            while (!done && !error && timeout_cnt < TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (error) begin
                $display("[TB] ERRO: co-processador sinalizou ERROR.");
            end else if (timeout_cnt >= TIMEOUT_CYCLES) begin
                $display("[TB] TIMEOUT: inferência não terminou em %0d ciclos.", TIMEOUT_CYCLES);
            end else begin
                $display("[TB] DONE após %0d ciclos.", cycles);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Fluxo principal
    // -------------------------------------------------------------------------
    initial begin
        // Dump de ondas para GTKWave
        $dumpfile("elm_accel_tb.vcd");
        $dumpvars(0, elm_accel_tb);

        // Carrega arquivos .hex gerados pelos scripts Python
        // Ajuste os caminhos conforme necessário
        $readmemh("img.hex",    img_mem);
        $readmemh("w_in.hex",   w_in_mem);
        $readmemh("b.hex",      b_mem);
        $readmemh("beta_q.hex", beta_mem);

        $display("=================================================");
        $display("  ELM Accelerator Testbench");
        $display("  Compare pred abaixo com: python3 golden_model.py");
        $display("=================================================");

        // 1. Reset
        do_reset;

        // 2. Carregar dados
        load_image;
        load_w_in;
        load_b;
        load_beta;

        // 3. Executar inferência
        run_inference;

        // 4. Resultado
        $display("-------------------------------------------------");
        if (!error && timeout_cnt < TIMEOUT_CYCLES) begin
            $display("  PREDICAO HARDWARE : %0d", pred);
            $display("  Ciclos            : %0d", cycles);
            $display("  Comparar com saida do golden_model.py");
        end
        $display("=================================================");

        #(CLK_PERIOD * 10);
        $finish;
    end

endmodule