module mac_dpth #(
    parameter ACC_W = 40
)(
    input  wire        [15:0] d_in,
    input  wire signed [15:0] peso,
    input  wire signed [15:0] bias,
    input  wire               clk, rst, clear, en,
    input  wire               is_layer_output,
    output reg  signed [15:0] out
);

    // Extensão de sinal da entrada
    wire signed [15:0] d_in_signed;
    assign d_in_signed = (!is_layer_output) ?
                         $signed({8'b0, d_in[7:0]}) :
                         $signed(d_in);

    // Produto em 32 bits (Q4.20 para pixel, Q8.24 para Q4.12)
    wire signed [31:0] prod_raw;
    assign prod_raw = d_in_signed * peso;

    // Extensão para ACC_W antes do shift
    wire signed [ACC_W-1:0] prod_extended;
    assign prod_extended = {{(ACC_W-32){prod_raw[31]}}, prod_raw};

    // Alinhamento para Q8.24 em ambos os caminhos
    wire signed [ACC_W-1:0] prod_aligned;
    // Alinhamento para Q8.24
    assign prod_aligned = (!is_layer_output) ?
                          (prod_extended <<< 12) : 
                           prod_extended;

    reg signed [ACC_W-1:0] accumulator;

    always @(posedge clk or posedge rst) begin
        if (rst)
            accumulator <= 0;
        else if (clear)
            // bias Q4.12 → Q8.24: extender para ACC_W depois shift 12
            accumulator <= {{(ACC_W-16){bias[15]}}, bias} <<< 12;
        else if (en)
            accumulator <= accumulator + prod_aligned;
    end

    // Clamp e extração Q8.24 → Q4.12 (bits [27:12])
    localparam signed [ACC_W-1:0] MAX =  ({{(ACC_W-16){1'b0}}, 16'sh7FFF} <<< 12);
    localparam signed [ACC_W-1:0] MIN =  ({{(ACC_W-16){1'b1}}, 16'sh8000} <<< 12);

    always @(*) begin
        if      (accumulator > MAX) out = 16'sh7FFF;
        else if (accumulator < MIN) out = 16'sh8000;
        else                        out = accumulator[27:12];
    end

endmodule