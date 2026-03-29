module elm_accel (
    input  wire       CLOCK_50,     
    input  wire [3:0] KEY,          
    input  wire [9:0] SW,           
    output wire [9:0] LEDR,         
    output reg  [6:0] HEX0        
);

    // --- Sinais Internos ---
    wire rst = ~KEY[0];
    wire start = SW[0];
    
    wire [16:0] w_addr;
    wire [6:0]  b_addr;
    wire [10:0] bt_addr;
    wire [9:0]  i_addr;
    
    wire m_clear, m_en, is_out;
    wire signed [15:0] m_out;
    wire a_en;
    wire signed [15:0] a_out;
    
    wire arg_start, arg_valid, arg_done;
    wire signed [15:0] y_to_arg;
    wire [3:0] arg_idx_in;
    wire [3:0] final_digit; 

    wire signed [15:0] q_weight, q_bias, q_beta, q_pixel;
    wire signed [15:0] mac_weight_in;

    // --- FSM ---
    fsm fsmbraba (
        .clk(CLOCK_50), .rst(rst), .start(start), 
        .y_data_to_argmax(y_to_arg),
        .mac_clear(m_clear), .mac_en(m_en), .is_layer_output(is_out), .mac_out(m_out),
        .weight_addr(w_addr), .bias_addr(b_addr), .beta_addr(bt_addr), .img_addr(i_addr),
        .act_en(a_en), .act_out(a_out),
        .argmax_start(arg_start), .argmax_valid(arg_valid), .argmax_idx_in(arg_idx_in), .argmax_done(arg_done),
        .done(LEDR[9]) 
    );

    // --- MAC ---
    assign mac_weight_in = (is_out) ? q_beta : q_weight;
    mac_dpth #(.ACC_W(40)) main_mac (
        .clk(CLOCK_50), .rst(rst), .clear(m_clear), .en(m_en),
        .d_in(is_out ? 16'sh0000 : q_pixel), 
        .peso(mac_weight_in),
        .bias(q_bias),
        .is_layer_output(is_out),
        .out(m_out)
    );

    // --- Ativação ---
    act_pwl sigmoid(
        .x_q412(m_out), 
        .y_q412(a_out)
    );

    // --- Argmax ---
    Argmax argmax_inst ( 
        .clk(CLOCK_50), .rst(rst),
        .start_layer(arg_start), .valid_in(arg_valid),
        .data_in(y_to_arg),
        .curr_idx(arg_idx_in),
        .argmax_idx(final_digit),
        .done(arg_done)
    );

    // --- Memórias RAM-1Port ---
    W_inRAM mem_w (
        .address(w_addr), .clock(CLOCK_50), .data(16'd0), .wren(1'b0),
        .rden(!is_out && (m_en || m_clear)), // Ativo quando NÃO é camada de saída
        .q(q_weight)
    );
    
    biasRAM mem_b (
        .address(b_addr), .clock(CLOCK_50), .data(16'd0), .wren(1'b0),
        .rden(m_clear), 
        .q(q_bias)
    );
    
    betaRAM mem_bt (
        .address(bt_addr), .clock(CLOCK_50), .data(16'd0), .wren(1'b0),
        .rden(is_out && (m_en || m_clear)), // Ativo quando É camada de saída
        .q(q_beta)
    );
    
    imageRAM mem_i (
        .address(i_addr), .clock(CLOCK_50), .data(16'd0), .wren(1'b0),
        .rden(m_en), 
        .q(q_pixel)
    );

    // --- Decodificador 7-Segmentos ---
    always @(*) begin
        case (final_digit)
            4'h0: HEX0 = 7'b100_0000;
            4'h1: HEX0 = 7'b111_1001;
            4'h2: HEX0 = 7'b010_0100;
            4'h3: HEX0 = 7'b011_0000;
            4'h4: HEX0 = 7'b001_1001;
            4'h5: HEX0 = 7'b001_0010;
            4'h6: HEX0 = 7'b000_0010;
            4'h7: HEX0 = 7'b111_1000;
            4'h8: HEX0 = 7'b000_0000;
            4'h9: HEX0 = 7'b001_0000;
            default: HEX0 = 7'b111_1111;
        endcase
    end

endmodule