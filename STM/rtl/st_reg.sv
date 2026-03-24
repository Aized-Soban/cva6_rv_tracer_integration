module st_reg import st_pkg::*; (
    input  logic clk,
    input  logic rst_n,
    
    // Simplified AXI-Lite Write Interface (behavioral)
    input  logic        axi_wvalid,
    input  logic [31:0] axi_waddr,
    input  logic [63:0] axi_wdata,
    
    // Status from FIFOs
    input  logic        sp_ready_i,
    
    // Outputs to Microarchitecture
    output logic        pkt_en_o,
    output req_vec_t    req_vec_o,
    output logic [11:0] async_period,
    output logic        enable_o
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_en_o     <= 1'b0;
            req_vec_o    <= '0;
            async_period <= 12'h0;
            enable_o     <= 1'b1; // Default enabled
        end else begin
            pkt_en_o <= 1'b0; // Default: no packet generated this cycle
            
            if (axi_wvalid && sp_ready_i) begin
                case (axi_waddr[7:0])
                    REG_DMTS: begin
                        req_vec_o <= '{opcode: OP_D64MTS, data: axi_wdata, has_timestamp: 1'b1};
                        pkt_en_o <= 1'b1;
                    end
                    REG_DM: begin
                        req_vec_o <= '{opcode: OP_D64M, data: axi_wdata, has_timestamp: 1'b0};
                        pkt_en_o <= 1'b1;
                    end
                    REG_DTS: begin
                        req_vec_o <= '{opcode: OP_D64TS, data: axi_wdata, has_timestamp: 1'b1};
                        pkt_en_o <= 1'b1;
                    end
                    REG_D: begin
                        req_vec_o <= '{opcode: OP_D64, data: axi_wdata, has_timestamp: 1'b0};
                        pkt_en_o <= 1'b1;
                    end
                    REG_FLAG: begin
                        req_vec_o <= '{opcode: OP_FLAG, data: 64'h0, has_timestamp: 1'b0};
                        pkt_en_o <= 1'b1;
                    end
                    REG_CHANNEL: begin
                        req_vec_o <= '{opcode: OP_C8, data: {56'h0, axi_wdata[7:0]}, has_timestamp: 1'b0};
                        pkt_en_o <= 1'b1;
                    end
                    REG_SYNC: begin
                        async_period <= axi_wdata[11:0]; // Updates config, no packet emitted
                    end
                endcase
            end
        end
    end
endmodule