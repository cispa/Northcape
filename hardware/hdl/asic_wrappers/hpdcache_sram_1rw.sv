/*
 *  Copyright 2023 CEA*
 *  *Commissariat a l'Energie Atomique et aux Energies Alternatives (CEA)
 *
 *  SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
 *
 *  Licensed under the Solderpad Hardware License v 2.1 (the “License”); you
 *  may not use this file except in compliance with the License, or, at your
 *  option, the Apache License version 2.0. You may obtain a copy of the
 *  License at
 *
 *  https://solderpad.org/licenses/SHL-2.1/
 *
 *  Unless required by applicable law or agreed to in writing, any work
 *  distributed under the License is distributed on an “AS IS” BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
 *  License for the specific language governing permissions and limitations
 *  under the License.
 */
/*
 *  Authors       : Cesar Fuguet
 *  Creation Date : March, 2020
 *  Description   : SRAM blackbox model
 *  History       :
 */
module hpdcache_sram_1rw
#(
    parameter int unsigned ADDR_SIZE = 0,
    parameter int unsigned DATA_SIZE = 0,
    parameter int unsigned DEPTH = 2**ADDR_SIZE
)
(
`ifdef USE_POWER_PINS
    inout wire vccd1,
    inout wire vssd1,
`endif
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  cs,
    input  logic                  we,
    input  logic [ADDR_SIZE-1:0]  addr,
    input  logic [DATA_SIZE-1:0]  wdata,
    output logic [DATA_SIZE-1:0]  rdata
);

hpdcache_sram_sport #(
    .DATA_WIDTH(DATA_SIZE),
    .DATA_DEPTH(DEPTH)
) i_sram_sport(
`ifdef USE_POWER_PINS
    .vccd1,
    .vssd1,
`endif
    .clk_i(clk),
    .wdata_i(wdata),
    .wenable_i(we),
    .wmask_i({DATA_SIZE/8{we}}),
    .rdata_o(rdata),
    .addr_i(addr),
    .enable_i(cs)
);

endmodule
