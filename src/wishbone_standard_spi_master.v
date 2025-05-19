//******************************************************************************
//  file:     wishbone_standard_spi_master.v
//
//  author:   JAY CONVERTINO
//
//  date:     2025/04/30
//
//  about:    Brief
//  Wishbone Standard SPI Master core.
//
//  license: License MIT
//  Copyright 2025 Jay Convertino
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//******************************************************************************

`resetall
`default_nettype none

`timescale 1ns/100ps

/*
 * Module: wishbone_standard_spi_master
 *
 * Wishbone Standard based SPI Master device.
 *
 * Parameters:
 *
 *   ADDRESS_WIDTH    - Width of the uP address port, max 32 bit.
 *   BUS_WIDTH        - Width of the uP bus data port, only valid values are 2 or 4.
 *   WORD_WIDTH       - Width of each SPI Master word. This will also set the bits used in the TX/RX data registers. Must be less than or equal to BUS_WIDTH. VALID: 1 to 4.
 *   CLOCK_SPEED      - This is the aclk frequency in Hz, this is the the frequency used for the bus and is divided by the rate.
 *   SELECT_WIDTH     - Bit width of the slave select, defaults to 16 to match altera spi ip.
 *   DEFAULT_RATE_DIV - Default divider value of the main clock to use for the spi data output clock rate. 0 is 2 (2^(X+1) X is the DEFAULT_RATE_DIV)
 *   DEFAULT_CPOL     - Default clock polarity for the core (0 or 1).
 *   DEFAULT_CPHA     - Default clock phase for the core (0 or 1).
 *
 * Ports:
 *
 *   clk            - Clock for all devices in the core
 *   rst            - Positive reset
 *   s_wb_cyc       - Bus Cycle in process
 *   s_wb_stb       - Valid data transfer cycle
 *   s_wb_we        - Active High write, low read
 *   s_wb_addr      - Bus address
 *   s_wb_data_i    - Input data
 *   s_wb_sel       - Device Select
 *   s_wb_ack       - Bus transaction terminated
 *   s_wb_data_o    - Output data
 *   s_wb_err       - Active high when a bus error is present
 *   irq            - Interrupt when data is received
 *   sclk           - spi clock, should only drive output pins to devices.
 *   mosi           - transmit for master output
 *   miso           - receive for master input
 *   ss_n           - slave select output
 */
module wishbone_standard_spi_master #(
    parameter ADDRESS_WIDTH     = 32,
    parameter BUS_WIDTH         = 4,
    parameter WORD_WIDTH        = 4,
    parameter CLOCK_SPEED       = 100000000,
    parameter SELECT_WIDTH      = 16,
    parameter DEFAULT_RATE_DIV  = 0,
    parameter DEFAULT_CPOL      = 0,
    parameter DEFAULT_CPHA      = 0
  )
  (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     s_wb_cyc,
    input  wire                     s_wb_stb,
    input  wire                     s_wb_we,
    input  wire [ADDRESS_WIDTH-1:0] s_wb_addr,
    input  wire [BUS_WIDTH*8-1:0]   s_wb_data_i,
    input  wire [BUS_WIDTH-1:0]     s_wb_sel,
    output wire                     s_wb_ack,
    output wire [BUS_WIDTH*8-1:0]   s_wb_data_o,
    output wire                     s_wb_err,
    output wire                     irq,
    output wire                     sclk,
    output wire                     mosi,
    input  wire                     miso,
    output wire [SELECT_WIDTH-1:0]  ss_n
  );

  // var: up_rreq
  // uP read bus request
  wire                      up_rreq;
  // var: up_rack
  // uP read bus acknowledge
  wire                      up_rack;
  // var: up_raddr
  // uP read bus address
  wire  [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0] up_raddr;
  // var: up_rdata
  // uP read bus request
  wire  [31:0]              up_rdata;

  // var: up_wreq
  // uP write bus request
  wire                      up_wreq;
  // var: up_wack
  // uP write bus acknowledge
  wire                      up_wack;
  // var: up_waddr
  // uP write bus address
  wire  [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0] up_waddr;
  // var: up_wdata
  // uP write bus data
  wire  [31:0]              up_wdata;

  //Group: Instantianted Modules

  // Module: inst_up_wishbone_standard
  //
  // Module instance of up_wishbone_standard for the Wishbone Classic Standard bus to the uP bus.
  up_wishbone_standard #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH),
    .BUS_WIDTH(BUS_WIDTH)
  ) inst_up_wishbone_standard (
    .clk(clk),
    .rst(rst),
    .s_wb_cyc(s_wb_cyc),
    .s_wb_stb(s_wb_stb),
    .s_wb_we(s_wb_we),
    .s_wb_addr(s_wb_addr),
    .s_wb_data_i(s_wb_data_i),
    .s_wb_sel(s_wb_sel),
    .s_wb_ack(s_wb_ack),
    .s_wb_data_o(s_wb_data_o),
    .s_wb_err(s_wb_err),
    .up_rreq(up_rreq),
    .up_rack(up_rack),
    .up_raddr(up_raddr),
    .up_rdata(up_rdata),
    .up_wreq(up_wreq),
    .up_wack(up_wack),
    .up_waddr(up_waddr),
    .up_wdata(up_wdata)
  );

  // Module: inst_up_spi_master
  //
  // Module instance of up_spi_master creating a Logic wrapper for spi master axis bus cores to interface with uP bus.
  up_spi_master #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH),
    .BUS_WIDTH(BUS_WIDTH),
    .WORD_WIDTH(WORD_WIDTH),
    .CLOCK_SPEED(CLOCK_SPEED),
    .SELECT_WIDTH(SELECT_WIDTH),
    .DEFAULT_RATE_DIV(DEFAULT_RATE_DIV),
    .DEFAULT_CPOL(DEFAULT_CPOL),
    .DEFAULT_CPHA(DEFAULT_CPHA)
  ) inst_up_spi_master (
    .clk(clk),
    .rstn(~rst),
    .up_rreq(up_rreq),
    .up_rack(up_rack),
    .up_raddr(up_raddr),
    .up_rdata(up_rdata),
    .up_wreq(up_wreq),
    .up_wack(up_wack),
    .up_waddr(up_waddr),
    .up_wdata(up_wdata),
    .irq(irq),
    .sclk(sclk),
    .mosi(mosi),
    .miso(miso),
    .ss_n(ss_n)
  );

endmodule

`resetall
