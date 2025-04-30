#******************************************************************************
# file:    tb_cocotb_up.py
#
# author:  JAY CONVERTINO
#
# date:    2025/04/29
#
# about:   Brief
# Cocotb test bench
#
# license: License MIT
# Copyright 2025 Jay Convertino
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#
#******************************************************************************

import random
import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.utils import get_sim_time
from cocotb.triggers import FallingEdge, RisingEdge, Timer, Event
from cocotb.binary import BinaryValue
from cocotbext.spi import SpiBus, SpiConfig
from cocotbext.spi.devices.generic import SpiSlaveLoopback
from cocotbext.up.ad import upMaster

RX_DATA_REG = 0x00
TX_DATA_REG = 0x04
STATUS_REG = 0x08
CONTROL_REG = 0x0C
RESERVED = 0x10
SLAVE_SELECT_REG = 0x14
EOP_VALUE_REG = 0x18
CONTROL_EXT_REG = 0x1C

# Function: random_bool
# Return a infinte cycle of random bools
#
# Returns: List
def random_bool():
  temp = []

  for x in range(0, 256):
    temp.append(bool(random.getrandbits(1)))

  return itertools.cycle(temp)

# Function: start_clock
# Start the simulation clock generator.
#
# Parameters:
#   dut - Device under test passed from cocotb test function
def start_clock(dut):
  cocotb.start_soon(Clock(dut.clk, int(1000000000/dut.CLOCK_SPEED.value), units="ns").start())

# Function: reset_dut
# Cocotb coroutine for resets, used with await to make sure system is reset.
async def reset_dut(dut):
  dut.rstn.value = 0
  await Timer(20, units="ns")
  dut.rstn.value = 1

# Function: write_slave_test
# Coroutine that is identified as a test routine. Simply write data over uP bus to SPI mosi
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def write_slave_test(dut):

    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    spi_bus = SpiBus.from_entity(dut, cs_name="ss_n")

    spi_config = SpiConfig(
        word_width=int(dut.BUS_WIDTH.value*8),
        sclk_freq=int(dut.CLOCK_SPEED.value >> 2**(dut.DEFAULT_RATE_DIV.value+1)),
        cpol=dut.DEFAULT_CPOL.value != 0,
        cpha=dut.DEFAULT_CPHA.value != 0,
        msb_first=True,
        frame_spacing_ns=0,
        ignore_rx_value=None,
        cs_active_low=True,
    )

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    spi_loop = SpiSlaveLoopback(spi_bus, spi_config)

    await reset_dut(dut)

    for x in range(0, 256):
      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      # busy check that the transmit is ready.
      while(not (await up_master.read(STATUS_REG >> DIVISOR) & (1 << 6))):
        await RisingEdge(dut.clk)

      data = await spi_loop.get_contents()

      assert data == x, "DATA WRITTEN FOR TRANSMIT DOES NOT MATCH SPI SLAVE CONTENTS"


# Function: loop_test
# Coroutine that is identified as a test routine. Loop test SPI
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def loop_test(dut):

    recv = []
    send = []

    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    spi_bus = SpiBus.from_entity(dut, cs_name="ss_n")

    spi_config = SpiConfig(
        word_width=int(dut.BUS_WIDTH.value*8),
        sclk_freq=int(dut.CLOCK_SPEED.value >> 2**(dut.DEFAULT_RATE_DIV.value+1)),
        cpol=dut.DEFAULT_CPOL.value != 0,
        cpha=dut.DEFAULT_CPHA.value != 0,
        msb_first=True,
        frame_spacing_ns=0,
        ignore_rx_value=None,
        cs_active_low=True,
    )

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    spi_loop = SpiSlaveLoopback(spi_bus, spi_config)

    await reset_dut(dut)

    for x in range(0, 2**8):
      # busy check that the transmit is ready.
      while(not(await up_master.read(STATUS_REG >> DIVISOR) & (1 << 6))):
        await RisingEdge(dut.clk)

      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      send.append(x)

      # busy check that the receive is ready.
      while(not(await up_master.read(STATUS_REG >> DIVISOR) & (1 << 7))):
        await RisingEdge(dut.clk)

      temp = await up_master.read(RX_DATA_REG >> DIVISOR)

      recv.append(temp.integer)

    #flush and last word out of spi echo slave
    await up_master.write(TX_DATA_REG >> DIVISOR, 0)

    # busy check that the receive is ready.
    while(not(await up_master.read(STATUS_REG >> DIVISOR) & (1 << 7))):
      await RisingEdge(dut.clk)

    temp = await up_master.read(RX_DATA_REG >> DIVISOR)

    recv.append(temp.integer)

    #remove first element as its the contents of the SPI core at reset, NOT a valid echo value.
    recv.pop(0)

    for r, s in zip(recv, send):
      assert r == s, "DATA SENT DOES NOT EQUAL DATA RECEIVED"

# Function: IRRDY_test
# Coroutine that is identified as a test routine. Receive Ready interrupt test
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def IRRDY_test(dut):
    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    await reset_dut(dut)

    # enable interrupts and enable the receive ready.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 8 | 1 << 7)

    for x in range(0, 256):
      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      # wait for a rising edge on the irq. FUTURE: ADD TIMEOUT
      await RisingEdge(dut.irq)

      temp = await up_master.read(RX_DATA_REG >> DIVISOR)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      assert dut.irq.value.integer == 0, "IRQ IS HIGH AFTER READ"

# Function: ITRDY_test
# Coroutine that is identified as a test routine. Transmit Ready interrupt test
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def ITRDY_test(dut):
    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    await reset_dut(dut)

    # enable interrupts and enable the receive ready.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 8 | 1 << 6)

    for x in range(0, 256):
      # wait for a rising edge on the irq. FUTURE: ADD TIMEOUT
      await RisingEdge(dut.irq)

      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      assert dut.irq.value.integer == 0, "IRQ IS HIGH AFTER WRITE"

      temp = await up_master.read(RX_DATA_REG >> DIVISOR)

# Function: ITOE_test
# Coroutine that is identified as a test routine. Transmit Written when not ready interrupt test
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def ITOE_test(dut):
    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    await reset_dut(dut)

    # enable interrupts and enable the receive ready.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 8 | 1 << 4)

    for x in range(0, 256):
      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      assert dut.irq.value.integer == 1, "IRQ IS LOW AFTER DOUBLE WRITE"

      temp = await up_master.read(STATUS_REG >> DIVISOR)

      # check that the status TOE (transmit write not ready) bit is set.
      assert (temp & (1 << 4)) != 0, "TOE BIT IS NOT 1"

      # check that the status E (transmit or receive  not ready) bit is set.
      assert (temp & (1 << 8)) != 0, "E BIT IS NOT 1"

      await up_master.write(STATUS_REG >> DIVISOR, 0)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      assert dut.irq.value.integer == 0, "IRQ IS HIGH AFTER STATUS WRITE"

      temp = await up_master.read(STATUS_REG >> DIVISOR)

      # check that the status TOE (transmit write not ready) bit is cleared.
      assert (temp & (1 << 4)) == 0, "TOE BIT IS 1"

      # check that the status E (transmit or receive  not ready) bit is cleared.
      assert (temp & (1 << 8)) == 0, "E BIT IS 1"

      # busy check that the read is ready.
      while(not (await up_master.read(STATUS_REG >> DIVISOR) & (1 << 7))):
        await RisingEdge(dut.clk)

      temp = await up_master.read(RX_DATA_REG >> DIVISOR)

# Function: IROE_test
# Coroutine that is identified as a test routine. Receive was never read, we missed data.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def IROE_test(dut):
    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    spi_bus = SpiBus.from_entity(dut, cs_name="ss_n")

    spi_config = SpiConfig(
        word_width=int(dut.BUS_WIDTH.value*8),
        sclk_freq=int(dut.CLOCK_SPEED.value >> 2**(dut.DEFAULT_RATE_DIV.value+1)),
        cpol=dut.DEFAULT_CPOL.value != 0,
        cpha=dut.DEFAULT_CPHA.value != 0,
        msb_first=True,
        frame_spacing_ns=0,
        ignore_rx_value=None,
        cs_active_low=True,
    )

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    spi_loop = SpiSlaveLoopback(spi_bus, spi_config)

    await reset_dut(dut)

    # enable interrupts and enable the receive error.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 8 | 1 << 3)

    for x in range(0, 256):
      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      while(not (await up_master.read(STATUS_REG >> DIVISOR) & (1 << 6))):
        await RisingEdge(dut.clk)

      await up_master.write(TX_DATA_REG >> DIVISOR, x)

      while(not (await up_master.read(STATUS_REG >> DIVISOR) & (1 << 6))):
        await RisingEdge(dut.clk)

      await RisingEdge(dut.clk)

      assert dut.irq.value.integer == 1, "IRQ IS LOW AFTER READ MISSED"

      temp = await up_master.read(STATUS_REG >> DIVISOR)

      # check that the status ROE (receive write not ready) bit is set.
      assert (temp & (1 << 3)) != 0, "ROE BIT IS NOT 1"

      # check that the status E (transmit or receive  not ready) bit is set.
      assert (temp & (1 << 8)) != 0, "E BIT IS NOT 1"

      await up_master.write(STATUS_REG >> DIVISOR, 0)

      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      temp = await up_master.read(STATUS_REG >> DIVISOR)

      # check that the status ROE (receive write not ready) bit is cleared.
      assert (temp & (1 << 3)) == 0, "ROE BIT IS 1"

      # check that the status E (transmit or receive  not ready) bit is cleared.
      assert (temp & (1 << 8)) == 0, "E BIT IS 1"

      assert dut.irq.value.integer == 0, "IRQ IS HIGH AFTER STATUS WRITE"

# Function: SSO_assert_test
# Coroutine that is identified as a test routine. Write control SS bit to assert all enable lines.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def SSO_assert_test(dut):
    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    await reset_dut(dut)

    # enable interrupts and enable the receive error.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 10)

    for x in range(0, 256):
      await RisingEdge(dut.clk)
      await RisingEdge(dut.clk)

      assert dut.ss_n.value.integer == 0, "SS_N IS NOT ZERO"

# Function: end_of_packet_test
# Coroutine that is identified as a test routine. check if the packet 0xAA has been added every 10th word.
# No check on EOP receive at the moment.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def end_of_packet_test(dut):

    start_clock(dut)

    DIVISOR = int(dut.BUS_WIDTH.value/2);

    spi_bus = SpiBus.from_entity(dut, cs_name="ss_n")

    spi_config = SpiConfig(
        word_width=int(dut.BUS_WIDTH.value*8),
        sclk_freq=int(dut.CLOCK_SPEED.value >> 2**(dut.DEFAULT_RATE_DIV.value+1)),
        cpol=dut.DEFAULT_CPOL.value != 0,
        cpha=dut.DEFAULT_CPHA.value != 0,
        msb_first=True,
        frame_spacing_ns=0,
        ignore_rx_value=None,
        cs_active_low=True,
    )

    up_master = upMaster(dut, "up", dut.clk, dut.rstn)

    spi_loop = SpiSlaveLoopback(spi_bus, spi_config)

    await reset_dut(dut)

    # enable interrupts and enable the eop caught.
    await up_master.write(CONTROL_REG >> DIVISOR, 1 << 8 | 1 << 9)

    await up_master.write(EOP_VALUE_REG >> DIVISOR, 0xFF)

    for x in range(0, 255):
      if((x%10 == 0) and (x != 0)):
        await up_master.write(TX_DATA_REG >> DIVISOR, 0xFF)

        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)

        temp = await up_master.read(STATUS_REG >> DIVISOR)

        assert (temp & (1 << 9)) != 0, "END OF PACKATE NOT ASSERTED ON TX WRITE"

        assert dut.irq.value.integer != 0, "IRQ IS NOT ACTIVE"
      else:
        await up_master.write(TX_DATA_REG >> DIVISOR, x)

      # busy check that the transmit is ready.
      while(not (await up_master.read(STATUS_REG >> DIVISOR) & (1 << 6))):
        await RisingEdge(dut.clk)

      data = await spi_loop.get_contents()

      if((x%10 == 0) and (x != 0)):
        assert data == 0xFF, "DATA WRITTEN FOR EOP DOES NOT MATCH SPI SLAVE CONTENTS"
      else:
        assert data == x, "DATA WRITTEN FOR TRANSMIT DOES NOT MATCH SPI SLAVE CONTENTS"

# Function: in_reset
# Coroutine that is identified as a test routine. This routine tests if device stays
# in unready state when in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def in_reset(dut):

    start_clock(dut)

    dut.rstn.value = 0

    await Timer(100, units="ns")

    assert dut.up_wack.value.integer == 0, "uP WACK is 1!"
    assert dut.up_rack.value.integer == 0, "uP RACK is 1!"

# Function: no_clock
# Coroutine that is identified as a test routine. This routine tests if no ready when clock is lost
# and device is left in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def no_clock(dut):

    dut.rstn.value = 0

    await Timer(100, units="ns")

    assert dut.up_wack.value.integer == 0, "uP WACK is 1!"
    assert dut.up_rack.value.integer == 0, "uP RACK is 1!"
