//******************************************************************************
// file:    up_spi_master.v
//
// author:  JAY CONVERTINO
//
// date:    2024/04/29
//
// about:   Brief
// uP Core for interfacing with axis spi that emulates the ALTERA SPI IP.
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
// IN THE SOFTWARE.
//
//******************************************************************************

`resetall
`default_nettype none

`timescale 1ns/100ps

/*
 * Module: up_spi_master
 *
 * SPI Master core with axis input/output data. Read/Write is size of BUS_WIDTH bytes. Write activates core for read.
 *
 * Parameters:
 *
 *   ADDRESS_WIDTH    - Width of the uP address port, max 32 bit.
 *   BUS_WIDTH        - Width of the uP bus data port, only valid values are 2 or 4.
 *   WORD_WIDTH       - Width of each SPI Master word. This will also set the bits used in the TX/RX data registers. Must be less than or equal to BUS_WIDTH, VALID: 1 to 4.
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
module up_spi_master #(
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
    input  wire                                     clk,
    input  wire                                     rstn,
    input  wire                                     up_rreq,
    output wire                                     up_rack,
    input  wire [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0]   up_raddr,
    output wire [(BUS_WIDTH*8)-1:0]                 up_rdata,
    input  wire                                     up_wreq,
    output wire                                     up_wack,
    input  wire [ADDRESS_WIDTH-(BUS_WIDTH/2)-1:0]   up_waddr,
    input  wire [(BUS_WIDTH*8)-1:0]                 up_wdata,
    output wire                                     irq,
    output wire                                     sclk,
    output wire                                     mosi,
    input  wire                                     miso,
    output wire [SELECT_WIDTH-1:0]                  ss_n
  );

  // var: DIVISOR
  // Divide the address register default location for 1 byte access to multi byte access. (register offsets are byte offsets).
  localparam DIVISOR = BUS_WIDTH/2;

  // var: REG_SIZE
  // Number of bits for the register address
  localparam REG_SIZE = 8;

  // Group: Register Information
  // Core has 7 registers at the offsets that follow when at a full 32 bit bus width, Internal address is OFFSET >> BUS_WIDTH/2 (32bit would be h4 >> 2 = 1 for internal address).
  //
  //  <RX_DATA_REG>       - h00
  //  <TX_DATA_REG>       - h04
  //  <STATUS_REG>        - h08
  //  <CONTROL_REG>       - h0C
  //  <RESERVED>          - h10
  //  <SLAVE_SELECT_REG>  - h14
  //  <EOP_VALUE_REG>     - h18
  //  <CONTROL_EXT_REG>   - h1C

  // Register Address: RX_DATA_REG
  // Defines the address offset for RX DATA OUTPUT
  // (see diagrams/reg_RX_DATA.png)
  // Valid bits are from WORD_WIDTH*8-1:0, which are data.
  localparam RX_DATA_REG = 8'h0 >> DIVISOR;
  // Register Address: TX_DATA_REG
  // Defines the address offset to write the TX DATA INPUT.
  // (see diagrams/reg_TX_DATA.png)
  // Valid bits are from WORD_WIDTH*8-1:0, which are data.
  localparam TX_DATA_REG = 8'h4 >> DIVISOR;
  // Register Address: STATUS_REG
  // Defines the address offset to read the status bits.
  // (see diagrams/reg_STATUS.png)
  localparam STATUS_REG  = 8'h8 >> DIVISOR;
  /* Register Bits: Status Register, 1 is considered active.
   *
   * EOP  - 9, This bit is active(1) when the EOP_VALUE_REG is equal to RX_DATA_REG or TX_DATA_REG.
   * E    - 8, Logical or of TOE and ROE (Clear by writing status).
   * RRDY - 7, Receive is ready (full) when the bit is 1, empty when the bit is 0.
   * TRDY - 6, Transmit is ready (empty) when the bit is 1, full when the bit is 0.
   * TMT  - 5, Transmit shift register empty is set to 1 when all bits have been output.
   * TOE  - 4, Transmit overrun is set to 1 when a TX_DATA_REG write happens whne TRDY is 1 (Clear by writing status reg).
   * ROE  - 3, Receive overrun is set to 1 when RRDY is 1 and a new received word is going to be written to RX_DATA_REG (Clear by writing status reg)
   */
  // Register Address: CONTROL_REG
  // Defines the address offset to set the control bits.
  // (see diagrams/reg_CONTROL.png)
  localparam CONTROL_REG = 8'hC >> DIVISOR;
  /* Register Bits: Control Register, 1 is considered active. All zeros on reset.
   *
   * SSO    - 10, Setting this to 1 will force all ss_n lines to 0 (selected).
   * IEOP   - 9, Generate a interrupt on EOP status bit going active if set to 1.
   * IE     - 8, Generate a interrupt on ANY error, active if set to 1.
   * IRRDY  - 7, Generate a interrupt on RRDY status bit going active if set to 1.
   * ITRDY  - 6, Generate a interrupt on TRDY status bit going active if set to 1.
   * ITOE   - 4, Generate a interrupt on TOE status bit going active if set to 1.
   * IROE   - 3, Generate a interrupt on ROE status bit going active if set to 1.
   */
   //
  localparam SSO_BIT    = 10;
  localparam IEOP_BIT   = 9;
  localparam IE_BIT     = 8;
  localparam IRRDY_BIT  = 7;
  localparam ITRDY_BIT  = 6;
  localparam ITOE_BIT   = 4;
  localparam IROE_BIT   = 3;
  // Register Address: RESERVED
  // Defines the address offset that is not used.
  localparam RESERVED = 8'h10 >> DIVISOR;
  // Register Address: SLAVE_SELECT_REG
  // Defines the address offset to set the slave select value
  // (see diagrams/reg_SLAVE_SELECT.png)
  // Valid bits are from SELECT_WIDTH-1:0, which are the slave select output lines to drive low during data transmission.
  localparam SLAVE_SELECT_REG = 8'h14 >> DIVISOR;
  // Register Address: EOP_VALUE_REG
  // Defines the address offset to set the end of packet match value
  // (see diagrams/reg_EOP.png)
  // Valid bits are from BUS_WIDTH*8:0, which are used to check for a word match between rx and/or tx and update status.
  localparam EOP_VALUE_REG = 8'h18 >> DIVISOR;
  // Register Address: CONTROL_EXT_REG
  // Defines the address offset for control register extensions
  // (see diagrams/reg_CONTROL_EXT.png)
  localparam CONTROL_EXT_REG = 8'h1C >> DIVISOR;
  /* Register Bits: Control Extension to add capabilities to Altera IP core.
   *
   * CPHA     - 5, Clock Phase Bit, 0 or 1 per SPI specs (default value set by IP parameter).
   * CPOL     - 4, Clock Polarity bit, 0 or 1 per SPI specs (default value set by IP parameter).
   * RATE_TOP - 3, Top bit for rate control. Divider values are 0 to 15 (2^X+1 where X is the divider value).
   * RATE_BOT - 0, Bottom bit for rate control.
   */
   //
  localparam CPHA_BIT      = 5;
  localparam CPOL_BIT      = 4;
  localparam RATE_TOP_BIT  = 3;
  localparam RATE_BOT_BIT  = 0;

  //slave select can be overridden by the sso bit, which when set to 1 forces all spi selects to be active (0).
  wire [SELECT_WIDTH-1:0]   s_ss_n;
  //read the current count of bits shifted into the core input.
  wire [(BUS_WIDTH*8)-1:0]  miso_dcount;
  //read the current count of bits presented on output.
  wire [(BUS_WIDTH*8)-1:0]  mosi_dcount;
  //if the mosi counter is 0, then the transmit shift register is empty and indicate this with a 1 (active).
  wire                      tmt;
  //error is r_toe or r_roe
  wire                      error;
  //read data from SPI core.
  wire [(WORD_WIDTH*8)-1:0]  rx_rdata;
  //transmit ready is the same as AXIS input (slave) tready.
  wire                      trdy;
  //receive ready is the same as AXIS output (master) valid.
  wire                      rrdy;

  //verilog reg

  reg [(WORD_WIDTH*8)-1:0] r_tx_wdata;
  // on tx register write enable data push to core (ignored if not ready).
  reg                     r_tx_wen;
  // on rx register read enable data pop from core (invalid values if not ready).
  reg                     r_rx_ren;
  // store inversion of tready on transmit write to indicate transmitter overrun error.
  reg                     r_toe;
  reg                     r_roe;

  // end of packet value matches current tx or rx value (this is true till the value is removed).
  reg                     r_eop;

  //up registers
  reg                     r_up_rack;
  reg [(BUS_WIDTH*8)-1:0] r_up_rdata;
  reg                     r_up_wack;

  //data registers
  reg [(BUS_WIDTH*8)-1:0] r_rx_data_reg;
  reg                     r_rx_data_full;

  //control registers
  reg [(BUS_WIDTH*8)-1:0] r_control_reg;
  reg [(BUS_WIDTH*8)-1:0] r_control_ext_reg;

  //slave selectSSO_BIT
  reg [SELECT_WIDTH-1:0]   r_slave_select_reg;

  //end of packet value
  reg [(BUS_WIDTH*8)-1:0] r_eop_reg;

  //interrupt
  reg                     r_irq;

  //spi rate is some value that is the clock rate divided by a power of two(from 2 to 16 (rate+1))
  reg [31:0]              r_spi_rate;

  //output signals assigned to registers.
  assign up_rack  = r_up_rack;
  assign up_wack  = r_up_wack;
  assign up_rdata = r_up_rdata;
  assign irq      = r_irq;

  assign error    = r_toe | r_roe;

  //we are currently not transmitting and are empty,
  assign tmt      = (mosi_dcount == 0 ? 1'b1 : 1'b0);

  //force select of all devices when control reg bit set to 1.
  assign ss_n = (r_control_reg[SSO_BIT] == 1'b1 ? 0 : s_ss_n);

  //up registers decoder
  always @(posedge clk)
  begin
    if(rstn == 1'b0)
    begin
      r_up_rack   <= 1'b0;
      r_up_wack   <= 1'b0;
      r_tx_wen    <= 1'b0;
      r_rx_ren    <= 1'b0;
      r_eop       <= 1'b0;
      r_toe       <= 1'b0;
      r_roe       <= 1'b0;
      r_up_rdata  <= 0;

      r_control_reg     <= 0;
      r_control_ext_reg <= 0;
      r_eop_reg         <= 0;
      //per alteras IP spec
      r_slave_select_reg <= 1;
      //extension register setup, duplicate Altera by using parameter defaults.
      //future extended drivers will be able to manipulate this.
      r_control_ext_reg[CPOL_BIT] <= DEFAULT_CPOL;
      r_control_ext_reg[CPHA_BIT] <= DEFAULT_CPHA;
      r_control_ext_reg[RATE_TOP_BIT:RATE_BOT_BIT] <= DEFAULT_RATE_DIV;
      r_spi_rate <= CLOCK_SPEED >> (r_control_ext_reg[RATE_TOP_BIT:RATE_BOT_BIT]+1);
    end else begin
      r_up_rack   <= 1'b0;
      r_up_wack   <= 1'b0;
      r_tx_wen    <= 1'b0;
      r_rx_ren    <= 1'b0;
      r_eop       <= 1'b0;

      r_toe <= r_toe;

      r_roe <= r_roe;

      r_up_rdata  <= r_up_rdata;

      r_up_rack <= up_rreq;

      r_spi_rate <= CLOCK_SPEED >> (r_control_ext_reg[RATE_TOP_BIT:RATE_BOT_BIT]+1);

      //if the transmit or receive words match the end of packet, set eop bit to 1.
      if(r_eop_reg[WORD_WIDTH*8-1:0] == r_tx_wdata || r_eop_reg[WORD_WIDTH*8-1:0] == rx_rdata)
      begin
        r_eop <= 1'b1;
      end

      //we have a overrun when the core has all its input data and we are ready
      //we are only ready because the previous word was never read.
      if(miso_dcount == WORD_WIDTH*8 && rrdy)
      begin
        r_roe <= 1'b1;
      end

      //read
      if(up_rreq == 1'b1)
      begin
        case(up_raddr[REG_SIZE-1:0])
          RX_DATA_REG: begin
            r_up_rdata <= {{((BUS_WIDTH-WORD_WIDTH)*8){1'b0}}, rx_rdata};
            r_rx_ren   <= 1'b1;
          end
          STATUS_REG: begin
            r_up_rdata <= {{(BUS_WIDTH*8-10){1'b0}}, r_eop, error, rrdy, trdy, tmt, r_toe, r_roe, 3'b000};
          end
          CONTROL_REG: begin
            r_up_rdata <= r_control_reg;
          end
          CONTROL_EXT_REG: begin
            r_up_rdata <= r_control_ext_reg;
          end
          SLAVE_SELECT_REG: begin
            r_up_rdata <= r_slave_select_reg;
          end
          EOP_VALUE_REG: begin
            r_up_rdata <= r_eop_reg;
          end
          default:begin
            r_up_rdata <= 0;
          end
        endcase
      end

      r_up_wack <= up_wreq;

      //write
      if(up_wreq == 1'b1)
      begin
        case(up_waddr[REG_SIZE-1:0])
          TX_DATA_REG: begin
            r_tx_wdata  <= up_wdata[(WORD_WIDTH*8)-1:0];
            r_tx_wen    <= 1'b1;
            r_toe       <= ~trdy;
          end
          STATUS_REG: begin
            r_toe <= 1'b0;
            r_roe <= 1'b0;
          end
          CONTROL_REG: begin
            r_control_reg <= up_wdata;
          end
          CONTROL_EXT_REG: begin
            r_control_ext_reg <= up_wdata;
          end
          SLAVE_SELECT_REG: begin
            r_slave_select_reg <= up_wdata;
          end
          EOP_VALUE_REG: begin
            r_eop_reg <= up_wdata;
          end
          default:begin
          end
        endcase
      end
    end
  end

  //irq generator
  always @(posedge clk)
  begin
    if(rstn == 1'b0)
    begin
      r_irq <= 1'b0;
    end else begin
      r_irq <= 1'b0;

      if((r_control_reg[IROE_BIT] | r_control_reg[IE_BIT]) & r_roe) r_irq <= 1'b1;

      if((r_control_reg[ITOE_BIT] | r_control_reg[IE_BIT]) & r_toe) r_irq <= 1'b1;

      if(r_control_reg[ITRDY_BIT] & trdy) r_irq <= 1'b1;

      if(r_control_reg[IRRDY_BIT] & rrdy) r_irq <= 1'b1;

      if(r_control_reg[IEOP_BIT] & r_eop) r_irq <= 1'b1;
    end
  end

  //Group: Instantiated Modules
  /*
   * Module: inst_axis_spi
   *
   * SPI Master instance with AXIS interface
   */
  axis_spi_master #(
    .CLOCK_SPEED(CLOCK_SPEED),
    .BUS_WIDTH(WORD_WIDTH),
    .SELECT_WIDTH(SELECT_WIDTH)
  ) inst_axis_spi_master (
    .aclk(clk),
    .arstn(rstn),
    .s_axis_tdata(r_tx_wdata),
    .s_axis_tvalid(r_tx_wen),
    .s_axis_tready(trdy),
    .m_axis_tdata(rx_rdata),
    .m_axis_tvalid(rrdy),
    .m_axis_tready(r_rx_ren),
    .sclk(sclk),
    .mosi(mosi),
    .miso(miso),
    .ssn_i(~r_slave_select_reg),
    .ssn_o(s_ss_n),
    .rate(r_spi_rate),
    .cpol(r_control_ext_reg[CPOL_BIT]),
    .cpha(r_control_ext_reg[CPHA_BIT]),
    .miso_dcount(miso_dcount),
    .mosi_dcount(mosi_dcount)
  );

endmodule

`resetall
