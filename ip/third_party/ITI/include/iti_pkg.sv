// Copyright (c) 2025 Thales DIS design services SAS
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Author: Maxime Colson - Thales
// Date: 20/03/2025
// Contributors: 
// Darshak Sheladiya, SYSGO GmbH
// Umberto Laghi, UNIBO

// This package is temporary, the idea is to have it directly in the encoder later

package iti_pkg;

  localparam CAUSE_LEN = 5;  //Size is ecause_width_p in the E-Trace SPEC
  localparam ITYPE_LEN = 3;  //Size is itype_width_p in the E-Trace SPEC (3 or 4)
  localparam IRETIRE_LEN = 32;  //Size is iretire_width_p in the E-Trace SPEC

  typedef enum logic [ITYPE_LEN-1:0] {
    STANDARD = 0,  // none of the other named itype codes
    EXC = 1,  // exception
    INT = 2,  // interrupt
    ERET = 3,  // exception or interrupt return
    NON_TAKEN_BR = 4,  // nontaken branch
    TAKEN_BR = 5,  // taken branch
    UNINF_JMP = 6,  // uninferable jump if ITYPE_LEN == 3, otherwise reserved
    RES = 7  /*, // reserved
    UC = 8, // uninferable call
    IC = 9, // inferable call
    UIJ = 10, // uninferable jump
    IJ = 11, // inferable jump
    CRS = 12, // co-routine swap
    RET = 13, // return
    OUIJ = 14, // other uninferable jump
    OIJ = 15*/  // other inferable jump
  } itype_t;
  
  localparam int NR_COMMIT_PORTS = 2;
  localparam int XLEN            = 64;

  typedef struct packed {
    logic [NR_COMMIT_PORTS-1:0]             valid;
    logic [NR_COMMIT_PORTS-1:0][XLEN-1:0]   pc;
    ariane_pkg::fu_op [NR_COMMIT_PORTS-1:0] op;
    logic [NR_COMMIT_PORTS-1:0]             is_compressed;
    logic [NR_COMMIT_PORTS-1:0]             is_taken;
    logic                                   ex_valid;
    logic [XLEN-1:0]                        tval;
    logic [XLEN-1:0]                        cause;
    riscv::priv_lvl_t                       priv_lvl;
    logic [63:0]                            cycles;
  } rvfi_to_iti_t;
  


  typedef struct packed {
    logic [NR_COMMIT_PORTS-1:0]                valid;
    logic [NR_COMMIT_PORTS-1:0][iti_pkg::IRETIRE_LEN-1:0] iretire;
    logic [NR_COMMIT_PORTS-1:0]                ilastsize;
    iti_pkg::itype_t [NR_COMMIT_PORTS-1:0]     itype;
    logic [iti_pkg::CAUSE_LEN-1:0]             cause;
    logic [XLEN-1:0]                           tval;
    riscv::priv_lvl_t                          priv;
    logic [NR_COMMIT_PORTS-1:0][XLEN-1:0]      iaddr;
    logic [63:0]                               cycles;
  } iti_to_encoder_t;
  
endpackage
