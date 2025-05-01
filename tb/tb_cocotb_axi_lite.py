#******************************************************************************
# file:    tb_cocotb_axi_lite.py
#
# author:  JAY CONVERTINO
#
# date:    2025/03/04
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
from cocotbext.axi import AxiLiteBus, AxiLiteMaster

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
  cocotb.start_soon(Clock(dut.aclk, int(1000000000/dut.CLOCK_SPEED.value), units="ns").start())

# Function: reset_dut
# Cocotb coroutine for resets, used with await to make sure system is reset.
async def reset_dut(dut):
  dut.arstn.value = 0
  await Timer(5, units="ns")
  dut.arstn.value = 1

# Function: loop_data
# Coroutine that is identified as a test routine. Use echo slave to loop data, check write axi equals spi slave contents, axi writes equal axi reads.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def loop_data(dut):

    recv = []
    send = []

    start_clock(dut)

    spi_bus = SpiBus.from_entity(dut, cs_name="ss_n")

    spi_config = SpiConfig(
        word_width=int(dut.WORD_WIDTH.value*8),
        sclk_freq=int(dut.CLOCK_SPEED.value >> 2**(dut.DEFAULT_RATE_DIV.value+1)),
        cpol=dut.DEFAULT_CPOL.value != 0,
        cpha=dut.DEFAULT_CPHA.value != 0,
        msb_first=True,
        frame_spacing_ns=0,
        ignore_rx_value=None,
        cs_active_low=True,
    )

    axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.aclk, dut.arstn, False)

    spi_loop = SpiSlaveLoopback(spi_bus, spi_config)

    await reset_dut(dut)

    # enable interrupt when data ready to read.
    await axil_master.write(CONTROL_REG, int(1 << 8 | 1 << 7).to_bytes(dut.BUS_WIDTH.value, "little"))

    for x in range(0, 2**8):
        payload_bytes = x.to_bytes(dut.WORD_WIDTH.value, "little")

        send.append(x)

        await axil_master.write(TX_DATA_REG, payload_bytes)

        # wait for a rising edge on the irq. FUTURE: ADD TIMEOUT
        await RisingEdge(dut.irq)

        data = await spi_loop.get_contents()

        assert data == x, "DATA WRITTEN FOR TRANSMIT DOES NOT MATCH SPI SLAVE CONTENTS"

        rx_data = await axil_master.read(RX_DATA_REG, dut.BUS_WIDTH.value)

        recv.append(int.from_bytes(rx_data.data, "little"))

    #flush and last word out of spi echo slave
    await axil_master.write(TX_DATA_REG, int(0).to_bytes(dut.BUS_WIDTH.value, "little"))

    # check that the receive is ready.
    await RisingEdge(dut.irq)

    rx_data = await axil_master.read(RX_DATA_REG, dut.BUS_WIDTH.value)

    recv.append(int.from_bytes(rx_data.data, "little"))

    #remove first element as its the contents of the SPI core at reset, NOT a valid echo value.
    recv.pop(0)

    for r, s in zip(recv, send):
      assert r == s, "DATA SENT DOES NOT EQUAL DATA RECEIVED"

# Function: in_reset
# Coroutine that is identified as a test routine. This routine tests if device stays
# in unready state when in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def in_reset(dut):

    start_clock(dut)

    dut.arstn.value = 0

    await Timer(100, units="ns")

    assert dut.s_axi_arready.value.integer == 0, "s_axi_aready is 1!"
    assert dut.s_axi_wready.value.integer == 0, "s_axi_wready is 1!"

# Function: no_clock
# Coroutine that is identified as a test routine. This routine tests if no ready when clock is lost
# and device is left in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def no_clock(dut):

    dut.arstn.value = 0

    await Timer(100, units="ns")

    assert dut.s_axi_arready.value.integer == 0, "s_axi_aready is 1!"
    assert dut.s_axi_wready.value.integer == 0, "s_axi_wready is 1!"
