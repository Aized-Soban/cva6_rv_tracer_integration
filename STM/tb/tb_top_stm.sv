`timescale 1ns / 1ps

// Assuming st_pkg is compiled in your environment. 
module tb_system_trace_top();

    // --- Time formatting for display ---
    initial $timeformat(-9, 0, " ns", 10);

    // --- Parameters ---
    parameter int AXI_ID_WIDTH   = 4;
    parameter int AXI_ADDR_WIDTH = 32;
    parameter int AXI_DATA_WIDTH = 64;

    // --- Signals ---
    logic        clk;
    logic        rst_n;
    
    // ==========================================================
    // --- FULL AXI4 SIGNALS ---
    // ==========================================================
    // Write Address Channel (AW)
    logic [AXI_ID_WIDTH-1:0]   s_axi_awid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [7:0]                s_axi_awlen;
    logic [2:0]                s_axi_awsize;
    logic [1:0]                s_axi_awburst;
    logic                      s_axi_awvalid;
    logic                      s_axi_awready;
    
    // Write Data Channel (W)
    logic [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    logic [7:0]                s_axi_wstrb;
    logic                      s_axi_wlast;
    logic                      s_axi_wvalid;
    logic                      s_axi_wready;
    
    // Write Response Channel (B)
    logic [AXI_ID_WIDTH-1:0]   s_axi_bid;
    logic [1:0]                s_axi_bresp;
    logic                      s_axi_bvalid;
    logic                      s_axi_bready;
    
    // Read Address Channel (AR)
    logic [AXI_ID_WIDTH-1:0]   s_axi_arid;
    logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    logic [7:0]                s_axi_arlen;
    logic [2:0]                s_axi_arsize;
    logic [1:0]                s_axi_arburst;
    logic                      s_axi_arvalid;
    logic                      s_axi_arready;
    
    // Read Data Channel (R)
    logic [AXI_ID_WIDTH-1:0]   s_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    logic [1:0]                s_axi_rresp;
    logic                      s_axi_rlast;
    logic                      s_axi_rvalid;
    logic                      s_axi_rready;

    // Timestamp
    logic [63:0] timestamp;
    
    // Encapsulator Interface
    logic        encap_ready_i;
    logic        encap_valid_o;
    logic [7:0]  encap_length_o;
    logic        encap_notime_o;
    logic [63:0] encap_timestamp_o;
    logic [87:0] encap_payload_o;

    // --- Mock Register Addresses (UPDATED TO MATCH st_pkg.sv) ---
    localparam [7:0] REG_DMTS    = 8'h00;
    localparam [7:0] REG_DM      = 8'h08;
    localparam [7:0] REG_DTS     = 8'h10;
    localparam [7:0] REG_D       = 8'h18;
    localparam [7:0] REG_FLAG    = 8'h20;
    localparam [7:0] REG_CHANNEL = 8'h28;
    localparam [7:0] REG_SYNC    = 8'h30;

    // --- DUT Instantiation ---
    system_trace_top #(
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        
        // AXI4 AW Channel
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        
        // AXI4 W Channel
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        
        // AXI4 B Channel
        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        
        // AXI4 AR Channel
        .s_axi_arid       (s_axi_arid),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arlen      (s_axi_arlen),
        .s_axi_arsize     (s_axi_arsize),
        .s_axi_arburst    (s_axi_arburst),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        
        // AXI4 R Channel
        .s_axi_rid        (s_axi_rid),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rlast      (s_axi_rlast),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),

        // System Interface
        .timestamp        (timestamp),
        .encap_ready_i    (encap_ready_i),
        .encap_valid_o    (encap_valid_o),
        .encap_length_o   (encap_length_o),
        .encap_notime_o   (encap_notime_o),
        .encap_timestamp_o(encap_timestamp_o),
        .encap_payload_o  (encap_payload_o)
    );

    // --- Clock & Timestamp Generation ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            timestamp <= 64'h1000; 
        else 
            timestamp <= timestamp + 64'd10; 
    end

    // --- AXI4 Single-Beat Write Task ---
    task write_reg(input logic [7:0] addr, input logic [63:0] data);
        // 1. Send Address (AW)
        @(posedge clk);
        s_axi_awid    <= '0;
        s_axi_awaddr  <= {24'h0, addr};
        s_axi_awlen   <= 8'h00;   // 0 means 1 beat
        s_axi_awsize  <= 3'b011;  // 8 bytes (64-bit)
        s_axi_awburst <= 2'b01;   // INCR burst type
        s_axi_awvalid <= 1'b1;
        
        wait(s_axi_awready);
        @(posedge clk);
        s_axi_awvalid <= 1'b0;

        // 2. Send Data (W)
        s_axi_wdata  <= data;
        s_axi_wstrb  <= 8'hFF;
        s_axi_wlast  <= 1'b1;     // Assert last since it's a 1-beat burst
        s_axi_wvalid <= 1'b1;
        
        wait(s_axi_wready);
        @(posedge clk);
        s_axi_wvalid <= 1'b0;
        s_axi_wlast  <= 1'b0;

        // 3. Wait for Write Response (B)
        s_axi_bready <= 1'b1;
        wait(s_axi_bvalid);
        @(posedge clk);
        s_axi_bready <= 1'b0;
        
        // Small delay to allow FIFO/Internal logic to process
        repeat(2) @(posedge clk); 
    endtask

    // --- Output Monitor (Prints to console visually Left-to-Right) ---
    always @(posedge clk) begin
        if (encap_valid_o && encap_ready_i) begin
            $display("--------------------------------------------------");
            $display("[%0t] PACKET EMITTED TO ENCAPSULATOR:", $time);
            $display("  Length (Bytes) : %0d", encap_length_o);
            $display("  No Time? (Flag): %b", encap_notime_o);
            $display("  Timestamp      : 0x%0h", encap_timestamp_o);
            
            // Print payload to match the MIPI diagram visually (Opcode first)
            $write("  Payload (Visual): 0x");
            
            if (encap_length_o == 1) begin
                $display("%02h", encap_payload_o[7:0]);
                
            end else if (encap_length_o == 2) begin
                $display("%02h_%02h", encap_payload_o[7:0], encap_payload_o[15:8]);
                
            end else if (encap_length_o == 9) begin
                $display("%02h_%016h", encap_payload_o[7:0], encap_payload_o[71:8]);
                
            end else if (encap_length_o == 11) begin
                $display("%02h_%020h", encap_payload_o[7:0], encap_payload_o[87:8]);
                
            end else begin
                $display("%0h (Raw Hex)", encap_payload_o);
            end
        end
    end

    // --- Main Test Sequence ---
    initial begin
        // 1. Initialize Signals
        rst_n         = 0;
        encap_ready_i = 1; 
        
        // Init AXI signals to 0
        s_axi_awid    = '0;
        s_axi_awaddr  = '0;
        s_axi_awlen   = '0;
        s_axi_awsize  = '0;
        s_axi_awburst = '0;
        s_axi_awvalid = 0;
        
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wlast   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        
        s_axi_arid    = '0;
        s_axi_araddr  = '0;
        s_axi_arlen   = '0;
        s_axi_arsize  = '0;
        s_axi_arburst = '0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        // 2. Apply Reset
        #20;
        rst_n = 1;
        #20;
        $display("\n--- Starting Trace Emulation Test (AXI4 Full) ---\n");

        // 3. Configure ASYNC Generator
        $display("[%0t] Configuring ASYNC period to 3", $time);
        write_reg(REG_SYNC, 64'h3);
        #20;

        // 4. Send Packet 1: FLAG (No Timestamp, Length 1)
        $display("[%0t] Sending FLAG packet", $time);
        write_reg(REG_FLAG, 64'h0);

        // 5. Send Packet 2: D64 (No Timestamp, Length 9)
        $display("[%0t] Sending D64 packet (No TS)", $time);
        write_reg(REG_D, 64'hDEADBEEF_CAFEBABE);

        // 6. Send Packet 3: D64TS (With Timestamp, Length 9)
        $display("[%0t] Sending D64TS packet (With TS)", $time);
        write_reg(REG_DTS, 64'h11223344_55667788);

        // Wait for FIFOs to drain out the ASYNC packet
        #100;

        // 7. Send Packet 4: Channel (No Timestamp, Length 2)
        $display("[%0t] Sending CHANNEL packet", $time);
        write_reg(REG_CHANNEL, 64'h00000000_000000FF);

        // 8. End Simulation
        #100;
        $display("\n--- Test Finished ---");
        $finish;
    end 

endmodule