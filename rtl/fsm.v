module fsm #(
    parameter   N_INPUTS  = 784,   
    parameter   N_HIDDEN  = 128,   
    parameter   N_OUTPUT  = 10     
)(
    input  wire clk,
    input  wire rst,
    input  wire start,// pulso para iniciar inferência
 
    // --- MAC ---
    output reg  mac_clear,       // 1 ciclo: carrega bias no acumulador
    output reg  mac_en,          // habilita acumulação
    output reg  is_layer_output, // 0=pixel, 1=Q4.12
	 input wire signed [15:0] mac_out,
 
    // ---Endereçamento de pesos/bias---
    output reg  [16:0] weight_addr, 
    output reg  [6:0]  bias_addr,   
	 output reg  [10:0] beta_addr,
 
    // ---Endereçamento de imagem---
    output reg  [9:0]  img_addr,
 
    // ---act_pwl---
    output reg  act_en,
    input  wire signed [15:0] act_out, 
 
    // ---Argmax---
    output reg  argmax_start,
    output reg  argmax_valid,
    output reg  [3:0] argmax_idx_in, // índice do neurônio de saída atual
    input  wire argmax_done,
	 output wire signed [15:0] y_data_to_argmax,
 
    // ---Resultado final---
    output reg  done
);

    localparam [2:0]
        IDLE         = 3'd0,
        HIDDEN_LAYER = 3'd1,  // acumula MAC para cada neurônio oculto
        ACTIVATE     = 3'd2,  // aplica act_pwl e salva h[] na RAM
        OUTPUT_LAYER = 3'd3,  // acumula MAC para cada neurônio de saída
        ARGMAX_ST    = 3'd4,  // alimenta módulo Argmax com os 10 resultados
        DONE_ST      = 3'd5;
 
    reg [2:0] state;
 
    // Contadores
    reg [9:0] pixel_cnt;    // entrada atual  (max 784)
    reg [6:0] neuron_cnt;   // neurônio oculto (0..127)
    reg [3:0] out_cnt;      // neurônio saída  (0..9)
 
    // RAM interna para h[128] em Q4.12
    reg signed [15:0] h_mem [0:N_HIDDEN-1];
    reg [6:0] h_waddr;  
    reg [6:0] h_raddr;  
    reg       h_wen;   
 
	 assign y_data_to_argmax = y_mem[argmax_idx_in];
	 
    // Escrita síncrona
    always @(posedge clk) begin
        if (h_wen)
            h_mem[h_waddr] <= act_out;
    end
 
    // RAM da camada de saída
    reg signed [15:0] y_mem [0:N_OUTPUT-1];
    reg [3:0] y_waddr;
    reg       y_wen;
    always @(posedge clk) begin
        if (y_wen)
            y_mem[y_waddr] <= mac_out;
    end
 
    // FSM principal
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            done         <= 1'b0;
            pixel_cnt    <= 10'd0;
            neuron_cnt   <= 7'd0;
            out_cnt      <= 4'd0;
            h_waddr      <= 7'd0;
            h_raddr      <= 7'd0;
            y_waddr      <= 4'd0;
            h_wen        <= 1'b0;
            y_wen        <= 1'b0;
            mac_clear    <= 1'b0;
            mac_en       <= 1'b0;
            is_layer_output <= 1'b0;
            act_en       <= 1'b0;
            argmax_start <= 1'b0;
            argmax_valid <= 1'b0;
            argmax_idx_in<= 4'd0;
            weight_addr  <= 17'd0;
            bias_addr    <= 8'd0;
            img_addr     <= 10'd0;
				beta_addr <= 11'd0;
        end
        else begin
            // Defaults (evita latch e pulsos espúrios)
            mac_clear    <= 1'b0;
            mac_en       <= 1'b0;
            h_wen        <= 1'b0;
            y_wen        <= 1'b0;
            act_en       <= 1'b0;
            argmax_start <= 1'b0;
            argmax_valid <= 1'b0;
            done         <= 1'b0;
 
            case (state)
                IDLE: begin
                    pixel_cnt  <= 10'd0;
                    neuron_cnt <= 7'd0;
                    out_cnt    <= 4'd0;
                    h_waddr    <= 7'd0;
                    y_waddr    <= 4'd0;
                    if (start) begin
                        state           <= HIDDEN_LAYER;
                        is_layer_output <= 1'b0;
                        // Bias do neurônio 0, clear no primeiro ciclo
                        bias_addr <= 8'd0;
                        mac_clear <= 1'b1;
                    end
                end
                HIDDEN_LAYER: begin
						  is_layer_output <= 1'b0;
						 // PASSO 1: Ciclo de Reset / Carregamento de Bias
						  if (pixel_cnt == 10'd0 && mac_clear == 1'b0) begin
							  bias_addr   <= neuron_cnt;
							  mac_clear   <= 1'b1;         
							  img_addr    <= 10'd0;        
							  weight_addr <= neuron_cnt * N_INPUTS; 
						  end
						  // PASSO 2: Acumulação (com proteção de latência)
						  else begin
							  mac_en <= 1'b1; 
							  if (pixel_cnt < N_INPUTS - 1) begin
									pixel_cnt   <= pixel_cnt + 1;
									img_addr    <= pixel_cnt + 1; // Aponta para o PRÓXIMO endereço
									weight_addr <= (neuron_cnt * N_INPUTS) + (pixel_cnt + 1);
							  end 
							  else begin
									mac_en  <= 1'b0;
									state   <= ACTIVATE;
									h_waddr <= neuron_cnt;
							  end
						 end
					 end
				    ACTIVATE: begin
                    act_en <= 1'b1;
                    h_wen  <= 1'b1; 
                    if (neuron_cnt == N_HIDDEN - 1) begin
                        state           <= OUTPUT_LAYER;
                        neuron_cnt      <= 7'd0;
                        pixel_cnt       <= 10'd0;
                        out_cnt         <= 4'd0;
                        is_layer_output <= 1'b1; 
                        mac_clear       <= 1'b1; 
                    end 
                    else begin
                        neuron_cnt <= neuron_cnt + 1;
                        pixel_cnt  <= 10'd0;
                        state      <= HIDDEN_LAYER;
                    end
                end
                OUTPUT_LAYER: begin
                    is_layer_output <= 1'b1;
                    if (pixel_cnt == 10'd0 && mac_clear == 1'b0) begin
                        mac_clear <= 1'b1;
                        beta_addr <= (out_cnt * N_HIDDEN); 
                        h_raddr   <= 7'd0; 
                    end
                    else begin
                        mac_en  <= 1'b1;
                        h_raddr <= pixel_cnt[6:0];
                        beta_addr <= (out_cnt * N_HIDDEN) + pixel_cnt;
                        if (pixel_cnt == N_HIDDEN - 1) begin
                            mac_en  <= 1'b0;
                            y_wen   <= 1'b1;
                            y_waddr <= out_cnt;
                            if (out_cnt == N_OUTPUT - 1) begin
                                state   <= ARGMAX_ST;
                                out_cnt <= 4'd0;
                            end
                            else begin
                                out_cnt   <= out_cnt + 1;
                                pixel_cnt <= 10'd0;
                            end
                        end
                        else begin
                            pixel_cnt <= pixel_cnt + 1;
                        end
                    end
                end
                ARGMAX_ST: begin
                    if (out_cnt == 4'd0) begin
                        argmax_start  <= 1'b1; // Pulso de reset/início no Argmax
                        argmax_valid  <= 1'b1;
                        argmax_idx_in <= 4'd0;
                        out_cnt       <= 4'd1;
                    end
                    else if (out_cnt < N_OUTPUT) begin
                        argmax_valid  <= 1'b1;
                        argmax_idx_in <= out_cnt;
                        out_cnt       <= out_cnt + 1;
                    end
                    else begin
                        // Já enviamos todos os 10 (0 a 9)
                        argmax_valid  <= 1'b0; 
                        if (argmax_done) begin
                            state <= DONE_ST;
                        end
                    end
                end
                DONE_ST: begin
                    done <= 1'b1;
                    if (!start)
                        state <= IDLE;
                end
            endcase
        end
    end
endmodule
 
