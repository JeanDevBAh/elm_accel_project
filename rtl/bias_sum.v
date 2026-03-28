module bias_sum(
input wire signed[15:0]bias,
input wire signed[15:0]mac_out,
output reg signed[15:0]resultado
);

wire signed[16:0]temp;

assign temp = {bias[15], bias} + {mac_out[15], mac_out};

always @(*) begin
        // Overflow Positivo: (P + P = N)
        if (bias[15] == 0 && mac_out[15] == 0 && temp[15] == 1) begin
            resultado = 16'h7FFF; // +7.999
        end
        // Overflow Negativo: (N + N = P)
        else if (bias[15] == 1 && mac_out[15] == 1 && temp[15] == 0) begin
            resultado = 16'h8000; // -8.000
        end
        else begin
            resultado = temp[15:0];
        end
    end
	 
endmodule