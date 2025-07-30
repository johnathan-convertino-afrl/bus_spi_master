//******************************************************************************
// file:    tb_cocotb_up.v
//
// author:  JAY CONVERTINO
//
// date:    2025/04/29
//
// about:   Brief
// Test bench wrapper for cocotb
//
// license: License MIT
// Copyright 2025 Jay Convertino
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.BUS_WIDTH
//
//******************************************************************************

`resetall
`default_nettype none

`timescale 1ns/100ps

/*
 * Module: tb_cocotb
 *
 * SPI Master core with axis input/output data. Read/Write is size of BUS_WIDTH bytes. Write activates core for read.
 *
 * Parameters:
 *
 *   ADDRESS_WIDTH    - Width of the uP address port, max 32 bit.
 *   BUS_WIDTH        - Width of the uP bus data port(can not be less than 2 bytes, max tested is 4).
 *   WORD_WIDTH       - Width of each SPI Master word. This will also set the bits used in the TX/RX data registers. Must be less than or equal to BUS_WIDTH 1 to 4.
 *   CLOCK_SPEED      - This is the aclk frequency in Hz, this is the the frequency used for the bus and is divided by the rate.
 *   SELECT_WIDTH     - Bit width of the slave select, defaults to 16 to match altera spi ip.
 *   DEFAULT_RATE_DIV - Default divider value of the main clock to use for the spi data output clock rate. 0 is 2 (2^(X+1) X is the DEFAULT_RATE_DIV)
 *   DEFAULT_CPOL     - Default clock polarity for the core (0 or 1).
 *   DEFAULT_CPHA     - Default clock phase for the core (0 or 1).
 *
 * Ports:
 *
 *   clk            - Clock for all devices in the core
 *   rstn           - Negative reset
 *   up_rreq        - uP bus read request
 *   up_rack        - uP bus read ack
 *   up_raddr       - uP bus read address
 *   up_rdata       - uP bus read data
 *   up_wreq        - uP bus write request
 *   up_wack        - uP bus write ack
 *   up_waddr       - uP bus write address
 *   up_wdata       - uP bus write data
 *   irq            - Interrupt when data is received
 *   sclk           - spi clock, should only drive output pins to devices.
 *   mosi           - transmit for master output
 *   miso           - receive for master input
 *   ss_n           - slave select output
 */
module tb_cocotb #(
    parameter ADDRESS_WIDTH     = 32,
    parameter BUS_WIDTH         = 4,
    parameter WORD_WIDTH        = 4,
    parameter CLOCK_SPEED       = 100000000,
    parameter SELECT_WIDTH      = 16,
    parameter DEFAULT_RATE_DIV  = 0,
    parameter DEFAULT_CPOL      = 0,
    parameter DEFAULT_CPHA      = 0,
    parameter FIFO_ENABLE       = 0
  )
  (
    input                                       clk,
    input                                       rstn,
    input                                       up_rreq,
    output                                      up_rack,
    input   [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0]   up_raddr,
    output  [(BUS_WIDTH*8)-1:0]                 up_rdata,
    input                                       up_wreq,
    output                                      up_wack,
    input   [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0]   up_waddr,
    input   [(BUS_WIDTH*8)-1:0]                 up_wdata,
    output                                      irq,
    output                                      sclk,
    output                                      mosi,
    input                                       miso,
    output  [SELECT_WIDTH-1:0]                  ss_n
  );
  // fst dump command
  initial begin
    $dumpfile ("tb_cocotb.fst");
    $dumpvars (0, tb_cocotb);
    #1;
  end

  //Group: Instantiated Modules

  /*
   * Module: dut
   *
   * Device under test, up_spi_master
   */
  up_spi_master #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH),
    .BUS_WIDTH(BUS_WIDTH),
    .WORD_WIDTH(WORD_WIDTH),
    .CLOCK_SPEED(CLOCK_SPEED),
    .SELECT_WIDTH(SELECT_WIDTH),
    .DEFAULT_RATE_DIV(DEFAULT_RATE_DIV),
    .DEFAULT_CPOL(DEFAULT_CPOL),
    .DEFAULT_CPHA(DEFAULT_CPHA),
    .FIFO_ENABLE(FIFO_ENABLE)
  ) dut (
    .clk(clk),
    .rstn(rstn),
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
