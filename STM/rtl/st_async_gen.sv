`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 18.03.2026 22:27:32
// Design Name: 
// Module Name: st_async_gen
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module st_async_gen import st_pkg::*; (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable_i,
    input  logic [11:0] async_period_i,
    input  logic        pkt_accept_i, // Pulsed when a packet is successfully queued
    
    output logic [87:0] async_payload_o,
    output logic        async_en_o
);

    logic [11:0] pkt_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pkt_counter     <= 12'h0;
            async_en_o      <= 1'b0;
            async_payload_o <= '0;
        end else begin
            async_en_o <= 1'b0; // Default pulse
            
            // If feature is disabled via software (period = 0), do nothing
            if (enable_i && async_period_i != 12'h0) begin
                if (pkt_accept_i) begin
                    if (pkt_counter >= async_period_i - 1) begin
                        async_en_o      <= 1'b1;
                        async_payload_o <= OP_ASYNC;
                        pkt_counter     <= 12'h0;
                    end else begin
                        pkt_counter <= pkt_counter + 1;
                    end
                end
            end else begin
                pkt_counter <= 12'h0;
            end
        end
    end
endmodule
