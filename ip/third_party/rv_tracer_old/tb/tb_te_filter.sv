// Copyright 2025 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
// SPDX-License-Identifier: SHL-0.51

// Author:  Umberto Laghi
// Contact: umberto.laghi2@unibo.it
// Github:  @ubolakes

`timescale 1ns/1ns

import te_pkg::*;

module tb_te_filter();

    logic clk;
    logic reset;

    // inputs
    logic                   trace_enable_i;
    // cause
    logic                   cause_filter_i;
    logic [XLEN-1:0]        upper_cause_i;
    logic [XLEN-1:0]        lower_cause_i;
    logic [XLEN-1:0]        match_cause_i;
    logic                   cause_mode_i;
    logic [XLEN-1:0]        cause_i;
    // tvec
    logic                   tvec_filter_i;
    logic [XLEN-1:0]        upper_tvec_i;
    logic [XLEN-1:0]        lower_tvec_i;
    logic [XLEN-1:0]        match_tvec_i;
    logic                   tvec_mode_i;
    logic [XLEN-1:0]        tvec_i;
    // tval
    logic                   tval_filter_i;
    logic [XLEN-1:0]        upper_tval_i;
    logic [XLEN-1:0]        lower_tval_i;
    logic [XLEN-1:0]        match_tval_i;
    logic                   tval_mode_i;
    logic [XLEN-1:0]        tval_i;
    // priv_lvl
    logic                   priv_lvl_filter_i;
    logic [PRIV_LEN-1:0]    upper_priv_lvl_i;
    logic [PRIV_LEN-1:0]    lower_priv_lvl_i;
    logic [PRIV_LEN-1:0]    match_priv_lvl_i;
    logic                   priv_lvl_mode_i;
    logic [PRIV_LEN-1:0]    priv_lvl_i;
    // iaddr (pc)
    logic                   iaddr_filter_i;
    logic [XLEN-1:0]        upper_iaddr_i;
    logic [XLEN-1:0]        lower_iaddr_i;
    logic [XLEN-1:0]        match_iaddr_i;
    logic                   iaddr_mode_i;
    logic [XLEN-1:0]        iaddr_i;

    // outputs
    logic                   nc_qualified_o;

    // testing output
    logic                   expected_nc_qualified;

    // iteration variable
    logic [31:0] i;

    // DUT instantiation
    te_filter DUT(
        .trace_enable_i(trace_enable_i),
        .cause_filter_i(cause_filter_i),
        .upper_cause_i(upper_cause_i),
        .lower_cause_i(lower_cause_i),
        .match_cause_i(match_cause_i),
        .cause_mode_i(cause_mode_i),
        .cause_i(cause_i),
        .tvec_filter_i(tvec_filter_i),
        .upper_tvec_i(upper_tvec_i),
        .lower_tvec_i(lower_tvec_i),
        .match_tvec_i(match_tvec_i),
        .tvec_mode_i(tvec_mode_i),
        .tvec_i(tvec_i),
        .tval_filter_i(tval_filter_i),
        .upper_tval_i(upper_tval_i),
        .lower_tval_i(lower_tval_i),
        .match_tval_i(match_tval_i),
        .tval_mode_i(tval_mode_i),
        .tval_i(tval_i),
        .priv_lvl_filter_i(priv_lvl_filter_i),
        .upper_priv_i(upper_priv_lvl_i),
        .lower_priv_i(lower_priv_lvl_i),
        .match_priv_i(match_priv_lvl_i),
        .priv_lvl_mode_i(priv_lvl_mode_i),
        .priv_i(priv_lvl_i),
        .iaddr_filter_i(iaddr_filter_i),
        .upper_iaddr_i(upper_iaddr_i),
        .lower_iaddr_i(lower_iaddr_i),
        .match_iaddr_i(match_iaddr_i),
        .iaddr_mode_i(iaddr_mode_i),
        .iaddr_i(iaddr_i),
        .nc_qualified_o(nc_qualified_o)
    );

    
    initial begin
        clk = 0;
        reset = 1;
        cause_filter_i = '0;
        tvec_filter_i  = '0;
        tval_filter_i = '0;
        priv_lvl_filter_i = '0;
        iaddr_filter_i = '0;
        #10;
        reset = 0;
        trace_enable_i = '1;// first test: all filters disabled -> all qualified
        #10;
        
        iaddr_filter_i  = '1;
        iaddr_mode_i = '1;  // Range mode = 0, equal mode = 1
        match_iaddr_i = 32'h0000_1000;  
        iaddr_i       = 32'h0000_1000; // equal
        #10;  // Second test : Address match mode , and should be qualified

        iaddr_filter_i  = '1;
        iaddr_mode_i = '1;  // Range mode = 0, equal mode = 1
        match_iaddr_i = 32'h0000_1000;  
        iaddr_i       = 32'h0000_1010; // not equal
        #10;  // Third test : Address match mode , and shouldnot be qualified

        iaddr_filter_i  = '1;
        iaddr_mode_i = '0;  // Range mode = 0, equal mode = 1
        lower_iaddr_i = 32'h0000_1000;  
        upper_iaddr_i = 32'h0000_2000;  
        iaddr_i       = 32'h0000_1010; // in range
        #10;  // Fourth test : Address range mode , and should be qualified

                iaddr_filter_i  = '1;
        iaddr_mode_i = '0;  // Range mode = 0, equal mode = 1
        lower_iaddr_i = 32'h0000_1000;  
        upper_iaddr_i = 32'h0000_2000;  
        iaddr_i       = 32'h0001_0000; // not in range
        #10;  // Fifth test : Address range mode , and shouldnot be qualified


    $finish();
    end
    always begin 
        clk <= 1; #5;
        clk <= 0; #5;
    end

endmodule