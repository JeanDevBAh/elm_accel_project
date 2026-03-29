module isa_instrcts (
    input  wire        clk, rst,
    // Interface Avalon-MM (vinda do HPS via HPS-to-FPGA bridge)
    input  wire [7:0]  avs_address,
    input  wire        avs_write,
    input  wire        avs_read,
    input  wire [31:0] avs_writedata,
    output reg  [31:0] avs_readdata,
    // Interface com FSM e memórias internas
    output reg         start,
    output reg  [9:0]  img_waddr,
    output reg  [7:0]  img_wdata,
    output reg         img_wen,
    input  wire        fsm_done,
    input  wire        fsm_busy,
    input  wire [3:0]  pred
);
    localparam ADDR_CMD    = 8'h00; // escrita: START / STORE_IMG
    localparam ADDR_PIXEL  = 8'h04; // escrita: dado + endereço do pixel
    localparam ADDR_STATUS = 8'h08; // leitura: {busy, done, error, pred}

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start   <= 0;
            img_wen <= 0;
        end else begin
            start   <= 0; // pulso de 1 ciclo
            img_wen <= 0;

            if (avs_write) begin
                case (avs_address)
                    ADDR_CMD: begin
                        if (avs_writedata[0]) start <= 1; // bit 0 = START
                    end
                    ADDR_PIXEL: begin
                        img_waddr <= avs_writedata[25:16]; // bits [25:16] = endereço
                        img_wdata <= avs_writedata[7:0];   // bits [7:0]  = pixel
                        img_wen   <= 1;
                    end
                endcase
            end

            if (avs_read) begin
                case (avs_address)
                    ADDR_STATUS: begin
                        avs_readdata <= {26'b0, fsm_busy, fsm_done, 1'b0, pred};
                        //               reserved  busy    done   error  pred[3:0]
                    end
                endcase
            end
        end
    end
endmodule