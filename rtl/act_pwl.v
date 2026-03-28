module act_pwl(
    input  wire signed [31:0] x_q412,
    output reg  signed [15:0] y_q412
);


    localparam signed [31:0] NEG6 = -32'sd24576; // -6.0 em Q4.12
    localparam signed [31:0] NEG2 = -32'sd8192;  // -2.0
    localparam signed [31:0] POS2 =  32'sd8192;  // +2.0
    localparam signed [31:0] POS6 =  32'sd24576; // +6.0
	 
    wire signed [31:0] seg_neg, seg_cen, seg_pos;

    assign seg_neg = 32'sd1024 + ((x_q412 + 32'sd8192)  >>> 4);
    assign seg_cen = 32'sd2048 +   (x_q412              >>> 3);
    assign seg_pos = 32'sd3072 + ((x_q412 - 32'sd8192)  >>> 4);

    always @(*) begin
        if      (x_q412 <= NEG6) y_q412 = 16'sd0;
        else if (x_q412 <= NEG2) y_q412 = seg_neg[15:0];
        else if (x_q412 <  POS2) y_q412 = seg_cen[15:0];
        else if (x_q412 <  POS6) y_q412 = seg_pos[15:0];
        else                     y_q412 = 16'sd4096;
    end

endmodule