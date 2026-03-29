module Argmax #(
    parameter NUM_CLASSES = 10,
    parameter IDX_W = $clog2(NUM_CLASSES)
)(
    input  wire clk,
    input  wire rst,
    input  wire start_layer,     
    input  wire valid_in,
    input  wire signed [15:0] data_in,
    input  wire [IDX_W-1:0]   curr_idx,
    output reg  [IDX_W-1:0]   argmax_idx,
    output reg                done
);

    reg signed [15:0] max_val_reg;
    reg               running;

    
    localparam [IDX_W-1:0] LAST_IDX = NUM_CLASSES - 1;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            max_val_reg  <= 16'sh8000;           
            argmax_idx   <= {IDX_W{1'b0}};
            running      <= 1'b0;
            done         <= 1'b0;
        end
        else begin
            done <= 1'b0;                        

            
            if (start_layer) begin
                running     <= 1'b1;
                max_val_reg <= 16'sh8000;
                argmax_idx  <= {IDX_W{1'b0}};
            end

          
            if ((running || start_layer) && valid_in) begin
              
                if (data_in > max_val_reg) begin
                    max_val_reg <= data_in;
                    argmax_idx  <= curr_idx;
                end

                if (curr_idx == LAST_IDX) begin
                    done    <= 1'b1;
                    running <= 1'b0;
                end
            end
        end
    end

endmodule