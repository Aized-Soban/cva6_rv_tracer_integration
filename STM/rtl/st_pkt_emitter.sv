module st_pkt_emitter import st_pkg::*; (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pkt_en_i,
    input  req_vec_t    req_vec_i,
    input  logic [63:0] timestamp_i,
    
    output trace_pkt_t  norm_pkt_o,
    output logic        valid_o
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o    <= 1'b0;
            norm_pkt_o <= '0;
        end else begin
            valid_o <= pkt_en_i;
            if (pkt_en_i) begin
                norm_pkt_o.opcode        <= req_vec_i.opcode;
                norm_pkt_o.payload_data  <= req_vec_i.data;
                norm_pkt_o.has_timestamp <= req_vec_i.has_timestamp; // Pass to encapsulator!
                norm_pkt_o.timestamp     <= req_vec_i.has_timestamp ? timestamp_i : 64'h0;
                
                // --- Length calculation logic ---
                // Calculates trace_payload length in BYTES (Opcode + Data)
                case (req_vec_i.opcode)
                    OP_FLAG:                              norm_pkt_o.length <= 8'd1; // 1 byte (Opcode only)
                    OP_C8:                                norm_pkt_o.length <= 8'd2; // 2 bytes (Opcode + 8b data)
                    OP_D64, OP_D64M, OP_D64TS, OP_D64MTS: norm_pkt_o.length <= 8'd9; // 9 bytes (Opcode + 64b data)
                    default:                              norm_pkt_o.length <= 8'd9; 
                endcase
            end
        end
    end
endmodule