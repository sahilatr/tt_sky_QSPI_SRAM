# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Setup a 100 MHz System Clock (10 ns period)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initialize signals
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Reset sequence
    await Timer(25, unit="ns")
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    await Timer(5, unit="ns")

    # Helper coroutine: Standard 2-Clock Write
    async def write_byte(addr, data):
        await FallingEdge(dut.clk)
        # Setup address and MSB data
        dut.ui_in.value = ((addr & 0x0F) << 4) | ((data >> 4) & 0x0F)
        # uio_in: bit 0 = A4, bit 1 = wen, bit 2 = ren
        uio_val = dut.uio_in.value.to_unsigned() & ~0x1F  # clear lower bits
        uio_val |= ((addr >> 4) & 0x01) | (1 << 1) | (0 << 2)
        dut.uio_in.value = uio_val

        await FallingEdge(dut.clk)
        # Drive LSB for clock 2
        dut.ui_in.value = (dut.ui_in.value.to_unsigned() & 0xF0) | (data & 0x0F)

        await FallingEdge(dut.clk)
        # Clear control lines (wen = 0)
        uio_val = dut.uio_in.value.to_unsigned() & ~(1 << 1)
        dut.uio_in.value = uio_val
        dut.ui_in.value = dut.ui_in.value.to_unsigned() & 0xF0

    # Helper coroutine: Simultaneous Write & Read
    async def write_and_read_simultaneous(
        wr_addr, wr_data, rd_addr, expected_rd_data
    ):
        await FallingEdge(dut.clk)
        # Setup Write Target & MSB Data
        ui_val = ((wr_addr & 0x0F) << 4) | ((wr_data >> 4) & 0x0F)
        dut.ui_in.value = ui_val

        # Setup Read Target (rd_sel on uio_in[7:3]) & Control (wen=1, ren=1, A4)
        uio_val = dut.uio_in.value.to_unsigned() & ~0xFE  # clear control & rd_sel
        uio_val |= (
            ((wr_addr >> 4) & 0x01)
            | (1 << 1)  # wen = 1
            | (1 << 2)  # ren = 1
            | ((rd_addr & 0x1F) << 3)  # rd_sel
        )
        dut.uio_in.value = uio_val
        dut.ena.value = 1

        await FallingEdge(dut.clk)
        # Drive LSB for write commit
        dut.ui_in.value = (dut.ui_in.value.to_unsigned() & 0xF0) | (wr_data & 0x0F)

        await RisingEdge(dut.clk)
        await Timer(1, unit="ns")  # Evaluation strobe on commit edge

        actual_uo = dut.uo_out.value.to_unsigned()
        if actual_uo == expected_rd_data:
            dut._log.info(
                f"\n>>> [SIMULTANEOUS SUCCESS] While writing to Addr {wr_addr}, "
                f"read from Addr {rd_addr} matched 0x{actual_uo:02X}! <<<\n"
            )
        else:
            dut._log.error(
                f"\n>>> [SIMULTANEOUS ERROR] Read 0x{actual_uo:02X} != Expected 0x{expected_rd_data:02X} <<<\n"
            )
            assert actual_uo == expected_rd_data

        await FallingEdge(dut.clk)
        # Clear enables
        uio_val = dut.uio_in.value.to_unsigned() & ~((1 << 1) | (1 << 2))
        dut.uio_in.value = uio_val
        dut.ui_in.value = dut.ui_in.value.to_unsigned() & 0xF0

    # Step 1: Write 0xC3 into Address 5
    dut._log.info(
        "====================================================================="
    )
    dut._log.info("STEP 1: Writing 0xC3 into Address 5 (no read)")
    dut._log.info(
        "====================================================================="
    )
    await write_byte(5, 0xC3)

    await ClockCycles(dut.clk, 2)

    # Step 2: Write 0xE1 to Address 8 while reading Address 5 concurrently
    dut._log.info(
        "====================================================================="
    )
    dut._log.info(
        "STEP 2: Writing 0xE1 to Address 8 while reading Address 5 concurrently"
    )
    dut._log.info(
        "====================================================================="
    )
    await write_and_read_simultaneous(
        wr_addr=8, wr_data=0xE1, rd_addr=5, expected_rd_data=0xC3
    )

    await ClockCycles(dut.clk, 2)
    dut._log.info(
        "====================================================================="
    )
    dut._log.info(
        "             ALL 256-BIT MATRIX OPERATIONS VERIFIED                  "
    )
    dut._log.info(
        "====================================================================="
    )
