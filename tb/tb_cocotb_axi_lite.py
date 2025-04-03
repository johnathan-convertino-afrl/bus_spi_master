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
from cocotbext.mil_std_1553 import MILSTD1553Source, MILSTD1553Sink
from cocotbext.axi import AxiLiteBus, AxiLiteMaster

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
  dut._log.info(f'CLOCK NS : {int(1000000000/dut.CLOCK_SPEED.value)}')
  cocotb.start_soon(Clock(dut.aclk, int(1000000000/dut.CLOCK_SPEED.value), units="ns").start())

# Function: reset_dut
# Cocotb coroutine for resets, used with await to make sure system is reset.
async def reset_dut(dut):
  dut.arstn.value = 0
  await Timer(5, units="ns")
  dut.arstn.value = 1

# Function: increment_test_cmd_send
# Coroutine that is identified as a test routine. Setup up to send 1553 commands
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def increment_test_cmd_send(dut):

    start_clock(dut)

    axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.aclk, dut.arstn, False)

    milstd1553_sink = MILSTD1553Sink(dut.o_diff)

    await reset_dut(dut)

    for x in range(0, 2**8):

        status = 0b10000001

        data = x

        payload = status << 16 | data

        payload_bytes = payload.to_bytes(4, "little")

        await axil_master.write(4, payload_bytes)

        rx_data = await milstd1553_sink.read_cmd()

        assert int.from_bytes(rx_data, "little") == x, "SENT COMMAND OVER UP DOES NOT MATCH RECEIVED DATA"


# Function: increment_test_cmd_recv
# Coroutine that is identified as a test routine. Setup up to recv 1553 commands
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def increment_test_cmd_recv(dut):

    start_clock(dut)

    await reset_dut(dut)

    axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.aclk, dut.arstn, False)

    milstd1553_source = MILSTD1553Source(dut.i_diff)

    for x in range(0, 2**8):

        data = x.to_bytes(2, byteorder="little")

        await milstd1553_source.write_cmd(data)

        status_reg = await axil_master.read(8, 4)

        rx_data = await axil_master.read(0, 4)

        assert int.from_bytes(rx_data.data, "little") & 0x0000FFFF == x, "RECEIVED COMMAND OVER UP DOES NOT MATCH SOURCE DATA"
        assert (int.from_bytes(rx_data.data, "little") >> 16) & 0xFF == 0b10000001, "RECEIVED DATA IS NOT A COMMAND OR PARITY FAILED"
        assert (int.from_bytes(status_reg.data, "little") >> 7) & 1 == 1, "PARITY CHECK FAILED"
        assert int.from_bytes(status_reg.data, "little") & 1 == 1, "RECEIVED DATA IS NOT VALID"

# Function: increment_test_data_send
# Coroutine that is identified as a test routine. Setup up to send 1553 data
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def increment_test_data_send(dut):

    start_clock(dut)

    await reset_dut(dut)

    axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.aclk, dut.arstn, False)

    milstd1553_sink = MILSTD1553Sink(dut.o_diff)

    for x in range(0, 2**8):

        status = 0b01000001

        data = x

        payload = status << 16 | data

        payload_bytes = payload.to_bytes(4, "little")

        await axil_master.write(4, payload_bytes)

        rx_data = await milstd1553_sink.read_data()

        assert int.from_bytes(rx_data, "little") == x, "SENT DATA OVER UP DOES NOT MATCH RECEIVED DATA"


# Function: increment_test_data_recv
# Coroutine that is identified as a test routine. Setup up to recv 1553 data
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def increment_test_data_recv(dut):

    start_clock(dut)

    await reset_dut(dut)

    axil_master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.aclk, dut.arstn, False)

    milstd1553_source = MILSTD1553Source(dut.i_diff)

    for x in range(0, 2**8):

        data = x.to_bytes(2, byteorder="little")

        await milstd1553_source.write_data(data)

        status_reg = await axil_master.read(8, 4)

        rx_data = await axil_master.read(0, 4)

        assert int.from_bytes(rx_data.data, "little") & 0x0000FFFF == x, "RECEIVED COMMAND OVER UP DOES NOT MATCH SOURCE DATA"
        assert (int.from_bytes(rx_data.data, "little") >> 16) & 0xFF == 0b01000001, "RECEIVED DATA IS NOT A COMMAND OR PARITY FAILED"
        assert (int.from_bytes(status_reg.data, "little") >> 7) & 1 == 1, "PARITY CHECK FAILED"
        assert int.from_bytes(status_reg.data, "little") & 1 == 1, "RECEIVED DATA IS NOT VALID"

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
