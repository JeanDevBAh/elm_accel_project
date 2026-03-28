module fsm(
    input  wire clk, rst,
    input  wire start,
    output reg  done
);

    // Estados Principais
    localparam IDLE           = 3'd0;
    localparam HIDDEN_LAYER   = 3'd1; // 784 -> 128
    localparam OUTPUT_LAYER   = 3'd2; // 128 -> 10
    localparam ARGMAX         = 3'd3; // Compara os 10
    localparam DONE_STATE     = 3'd4;

    reg [2:0] current_state;
    
    // Sinais de controlo internos para os contadores
    reg [9:0] pixel_cnt;   // Até 784
    reg [6:0] neuron_cnt;  // Até 128 (Camada Oculta)
    reg [3:0] out_neu_cnt; // Até 10 (Camada Saída)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE;
            done <= 0;
            // Reset de todos os contadores...
        end else begin
            case (current_state)
                
                IDLE: begin
                    done <= 0;
                    if (start) current_state <= HIDDEN_LAYER;
                end

                HIDDEN_LAYER: begin
                    // Lógica: Para cada neurónio (0 a 127), processa 784 pixels
                    // Aqui controlas o MAC_CLEAR e MAC_EN
                    if (neuron_cnt == 127 && pixel_cnt == 783) begin
                        current_state <= OUTPUT_LAYER;
                        neuron_cnt <= 0;
                        pixel_cnt <= 0;
                    end else begin
                        // Lógica de incremento de contadores (pixel primeiro, depois neurónio)
                    end
                end

                OUTPUT_LAYER: begin
                    // Lógica: Para cada neurónio de saída (0 a 9), processa as 128 entradas
                    // (que foram guardadas numa RAM intermédia vinda da HIDDEN_LAYER)
                    if (out_neu_cnt == 9 && pixel_cnt == 127) begin
                        current_state <= ARGMAX;
                    end
                end

                ARGMAX: begin
                    // Varre os 10 resultados finais para encontrar o maior índice
                    current_state <= DONE_STATE;
                end

                DONE_STATE: begin
                    done <= 1;
                    if (!start) current_state <= IDLE;
                end

            endcase
        end
    end
endmodule