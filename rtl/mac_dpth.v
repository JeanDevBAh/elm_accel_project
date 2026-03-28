module mac_dpth #(
    parameter ACC_W = 40  // largura do acumulador (recomendado >= 40)
)(
    input wire [15:0] d_in,           // Entrada (pixel ou Q4.12)
    input wire signed [15:0] peso,    // Q4.12
    input wire signed [15:0] bias,    // Q4.12
    input wire clk, rst, clear, en,
    input wire is_layer_output,       // 0: pixel | 1: Q4.12
    output reg signed [15:0] out      // Q4.12
);

    wire signed [15:0] d_in_signed;

    assign d_in_signed = (!is_layer_output) ?
                         $signed({8'b0, d_in[7:0]}) : // pixel (Q8.0)
                         $signed(d_in);               // saída anterior (Q4.12)

    wire signed [31:0] prod_raw;
    assign prod_raw = d_in_signed * peso;

    wire signed [31:0] prod_aligned;

    assign prod_aligned = (!is_layer_output) ?
                          (prod_raw <<< 12) : 
                          prod_raw;           

    reg signed [ACC_W-1:0] accumulator;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            accumulator <= 0;
        end 
        else if (clear) begin
            accumulator <= $signed(bias) <<< 12; // Q4.12 → Q8.24
        end 
        else if (en) begin
            accumulator <= accumulator + {{(ACC_W-32){prod_aligned[31]}}, prod_aligned};
        end
    end


    localparam signed [ACC_W-1:0] MAX =  (32'sd32767 <<< 12);
    localparam signed [ACC_W-1:0] MIN = -(32'sd32768 <<< 12);

    always @(*) begin
        if (accumulator > MAX)
            out = 16'sh7FFF;
        else if (accumulator < MIN)
            out = 16'sh8000;
        else
            out = accumulator[27:12]; // Q8.24 → Q4.12
    end

endmodule