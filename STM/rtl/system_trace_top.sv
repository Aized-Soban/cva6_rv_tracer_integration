module system_trace_top import st_pkg::*; #(
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // ==========================================================
    // --- FULL AXI4 SLAVE INTERFACE ---
    // ==========================================================
    // Write Address Channel (AW)
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,    // Burst Length
    input  logic [2:0]                s_axi_awsize,   // Burst Size
    input  logic [1:0]                s_axi_awburst,  // Burst Type
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    
    // Write Data Channel (W)
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [7:0]                s_axi_wstrb,
    input  logic                      s_axi_wlast,    // Last beat of burst
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    
    // Write Response Channel (B)
    output logic [AXI_ID_WIDTH-1:0]   s_axi_bid,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    
    // Read Address Channel (AR)
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    
    // Read Data Channel (R)
    output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,    // Last beat of read burst
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // ==========================================================
    // System Timestamp
    input  logic [63:0] timestamp,
    
    // --- DIRECT ENCAPSULATOR INTERFACE ---
    input  logic        encap_ready_i,     
    output logic        encap_valid_o,     
    output logic [7:0]  encap_length_o,    
    output logic        encap_notime_o,    
    output logic [63:0] encap_timestamp_o, 
    output logic [87:0] encap_payload_o    
);

    // --- Legacy Internal Signals for st_reg ---
    logic        axi_wvalid;
    logic [31:0] axi_waddr;
    logic [63:0] axi_wdata;

    // --- Internal Signals ---
    logic        pkt_en;
    req_vec_t    req_vec;
    logic [11:0] async_period;
    logic        enable_bundle;
    
    trace_pkt_t  norm_pkt;
    logic        norm_pkt_valid;
    
    logic [87:0] async_payload_raw;
    logic        async_en;
    logic        pkt_accept;

    // FIFO 1 Signals
    logic        fifo1_full, fifo1_empty;
    logic        fifo1_push, fifo1_pop;
    trace_pkt_t  fifo1_data_out;
    logic        fifo1_valid_out;
    
    // FIFO 2 Signals
    logic        fifo2_full, fifo2_empty;
    logic        fifo2_push, fifo2_pop;
    trace_pkt_t  fifo2_data_out;

    // MUX Signals
    trace_pkt_t  mux_data_out;
    logic        mux_valid_out;

    // ====================================================================
    // AXI4 FULL TO INTERNAL LEGACY BRIDGE (Write Burst FSM)
    // ====================================================================
    typedef enum logic [1:0] { W_IDLE, W_DATA, W_RESP } axi_wstate_t;
    axi_wstate_t wstate;

    logic [AXI_ID_WIDTH-1:0] latched_awid;
    logic [31:0]             latched_awaddr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate         <= W_IDLE;
            latched_awid   <= '0;
            latched_awaddr <= '0;
        end else begin
            case (wstate)
                W_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        latched_awid   <= s_axi_awid;
                        latched_awaddr <= s_axi_awaddr;
                        wstate         <= W_DATA;
                    end
                end
                
                W_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (s_axi_wlast) begin
                            wstate <= W_RESP; // End of burst
                        end else begin
                            // Auto-increment address for next beat in the burst (8 bytes for 64-bit bus)
                            latched_awaddr <= latched_awaddr + 8;
                        end
                    end
                end
                
                W_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        wstate <= W_IDLE;
                    end
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end

    // Write Channel Assignments
    assign s_axi_awready = (wstate == W_IDLE);
    assign s_axi_wready  = (wstate == W_DATA);
    assign s_axi_bvalid  = (wstate == W_RESP);
    assign s_axi_bresp   = 2'b00; // OKAY response
    assign s_axi_bid     = latched_awid;

    // Map the burst logic down to the single-cycle register interface
    assign axi_wvalid = (wstate == W_DATA) && s_axi_wvalid && s_axi_wready;
    assign axi_waddr  = latched_awaddr;
    assign axi_wdata  = s_axi_wdata;


    // ====================================================================
    // AXI4 FULL READ STUB (Safely returns 0s and handles RLAST)
    // ====================================================================
    typedef enum logic [1:0] { R_IDLE, R_DATA } axi_rstate_t;
    axi_rstate_t rstate;
    
    logic [AXI_ID_WIDTH-1:0] latched_arid;
    logic [7:0]              r_burst_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate       <= R_IDLE;
            latched_arid <= '0;
            r_burst_cnt  <= '0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        latched_arid <= s_axi_arid;
                        r_burst_cnt  <= s_axi_arlen; // Load burst length
                        rstate       <= R_DATA;
                    end
                end
                
                R_DATA: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (r_burst_cnt == 0) begin
                            rstate <= R_IDLE; // Read burst complete
                        end else begin
                            r_burst_cnt <= r_burst_cnt - 1;
                        end
                    end
                end
                default: rstate <= R_IDLE;
            endcase
        end
    end

    // Read Channel Assignments
    assign s_axi_arready = (rstate == R_IDLE);
    assign s_axi_rvalid  = (rstate == R_DATA);
    assign s_axi_rid     = latched_arid;
    assign s_axi_rdata   = 64'h0; // Write-only registers return 0
    assign s_axi_rresp   = 2'b00; // OKAY response
    assign s_axi_rlast   = (rstate == R_DATA) && (r_burst_cnt == 0);

    // ====================================================================
    // Module Instantiations
    // ====================================================================

    // 1. Software Register Interface (Unchanged internals)
    st_reg u_st_reg (
        .clk(clk),
        .rst_n(rst_n),
        .axi_wvalid(axi_wvalid), // Pulses once per beat in the burst
        .axi_waddr(axi_waddr),   
        .axi_wdata(axi_wdata),   
        .sp_ready_i(~fifo1_full),
        .pkt_en_o(pkt_en),
        .req_vec_o(req_vec),
        .async_period(async_period),
        .enable_o(enable_bundle)
    );

    // 2. Packet Emitter
    st_pkt_emitter u_st_pkt_emitter (
        .clk(clk),
        .rst_n(rst_n),
        .pkt_en_i(pkt_en),
        .req_vec_i(req_vec),
        .timestamp_i(timestamp),
        .norm_pkt_o(norm_pkt),
        .valid_o(norm_pkt_valid)
    );

    // 3. FIFO 1 (Buffers standard trace packets)
    assign fifo1_push = norm_pkt_valid & ~fifo1_full;
    
    fifo_v3 #(
        .DEPTH(16), 
        .dtype(trace_pkt_t) 
    ) u_fifo_v3_1 (
        .clk_i(clk),
        .rst_ni(rst_n),
        .flush_i(1'b0),
        .testmode_i(1'b0),
        .full_o(fifo1_full),
        .empty_o(fifo1_empty),
        .usage_o(), 
        .data_i(norm_pkt),
        .push_i(fifo1_push),
        .data_o(fifo1_data_out),
        .pop_i(fifo1_pop)
    );

    assign fifo1_valid_out = ~fifo1_empty;

    // 4. Async Generator
    st_async_gen u_st_async_gen (
        .clk(clk),
        .rst_n(rst_n),
        .enable_i(enable_bundle),
        .async_period_i(async_period),
        .pkt_accept_i(pkt_accept),
        .async_payload_o(async_payload_raw),
        .async_en_o(async_en)
    );

    // 5. Multiplexer Logic
    always_comb begin
        if (async_en) begin
            mux_data_out.opcode        = async_payload_raw[7:0]; 
            mux_data_out.payload_data  = async_payload_raw[71:8]; 
            mux_data_out.timestamp     = {40'h0, async_payload_raw[87:72]}; 
            mux_data_out.length        = 8'd11; 
            mux_data_out.has_timestamp = 1'b0;  
            mux_valid_out              = 1'b1;
        end else begin
            mux_data_out  = fifo1_data_out;
            mux_valid_out = fifo1_valid_out;
        end
    end

    // 6. FIFO Control & Handshaking
    assign fifo2_push = mux_valid_out & ~fifo2_full;
    assign fifo1_pop  = fifo1_valid_out & ~async_en & ~fifo2_full;
    assign pkt_accept = fifo1_valid_out && ~async_en && ~fifo2_full;

    // 7. FIFO 2
    fifo_v3 #(
        .DEPTH(16), 
        .dtype(trace_pkt_t) 
    ) u_fifo_v3_2 (
        .clk_i(clk),
        .rst_ni(rst_n),
        .flush_i(1'b0),
        .testmode_i(1'b0),
        .full_o(fifo2_full),
        .empty_o(fifo2_empty),
        .usage_o(), 
        .data_i(mux_data_out),
        .push_i(fifo2_push),
        .data_o(fifo2_data_out),
        .pop_i(fifo2_pop)
    );

    // 8. UNBUNDLING FOR ENCAPSULATOR
    assign encap_valid_o     = ~fifo2_empty;
    assign fifo2_pop         = encap_valid_o & encap_ready_i; 

    assign encap_length_o    = fifo2_data_out.length;
    assign encap_notime_o    = ~fifo2_data_out.has_timestamp; 
    assign encap_timestamp_o = fifo2_data_out.timestamp;
    
    assign encap_payload_o   = (fifo2_data_out.length == 8'd11) ? 
                               {fifo2_data_out.timestamp[15:0], fifo2_data_out.payload_data, fifo2_data_out.opcode} :
                               {16'h0, fifo2_data_out.payload_data, fifo2_data_out.opcode};

endmodule