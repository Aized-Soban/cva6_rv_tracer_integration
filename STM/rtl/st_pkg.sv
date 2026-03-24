package st_pkg;
    // Register Offsets
    localparam logic [7:0] REG_DMTS    = 8'h00;
    localparam logic [7:0] REG_DM      = 8'h08;
    localparam logic [7:0] REG_DTS     = 8'h10;
    localparam logic [7:0] REG_D       = 8'h18;
    localparam logic [7:0] REG_FLAG    = 8'h20;
    localparam logic [7:0] REG_CHANNEL = 8'h28;
    localparam logic [7:0] REG_SYNC    = 8'h30;
    localparam logic [7:0] REG_READY   = 8'h38;

    // MIPI System Trace Opcodes
    localparam logic [7:0]  OP_D64     = 8'h07;
    localparam logic [7:0]  OP_D64M    = 8'hFB;
    localparam logic [7:0]  OP_D64TS   = 8'hF7;
    localparam logic [7:0]  OP_D64MTS  = 8'h0B;
    localparam logic [7:0]  OP_FLAG    = 8'hFE;
    localparam logic [7:0]  OP_C8      = 8'h03;
    localparam logic [87:0] OP_ASYNC   = 88'hFFFF_FFFF_FFFF_FFFF_FFF0;

    // Struct for the request vector from reg to emitter
    typedef struct packed {
        logic [7:0]  opcode;
        logic [63:0] data;
        logic        has_timestamp;
    } req_vec_t;

    // Struct for internal packet formats before encapsulation
typedef struct packed {
        logic [7:0]  opcode;
        logic [63:0] payload_data;
        logic [63:0] timestamp;
        logic [7:0]  length;
        logic        has_timestamp; // <-- ADD THIS LINE
    } trace_pkt_t;
endpackage