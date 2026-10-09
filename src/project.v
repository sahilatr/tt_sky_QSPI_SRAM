/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

       // Fixed 8-Bit Secret Key for Parallel XOR Encryption & Decryption
    localparam [7:0] CIPHER_KEY = 8'b1010_1010; // 0xAA

    // ----------------------------------------------------------------
    // 1. Signal Mapping
    // ----------------------------------------------------------------
    wire       rst     = ~rst_n;
    wire       cs      = ena;
    wire [3:0] io_in   = ui_in[3:0];
    wire [4:0] wr_addr = {uio_in[0], ui_in[7:4]};  // {A4, A3, A2, A1, A0}
    wire       wen     = uio_in[1];
    wire       ren     = uio_in[2];
    wire [4:0] rd_sel  = uio_in[7:3];
    reg [7:0] data_out;

    assign uo_out = data_out;
    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    // ----------------------------------------------------------------
    // 2. Physical 256-Bit Memory Array & Registers
    // ----------------------------------------------------------------
    reg [3:0]   msb_buf;       // Buffer to hold upper nibble across Clock 1
    reg         nibble_phase;  // 0 = Waiting for MSB, 1 = Waiting for LSB
    reg [255:0] mem_cells;     // 256 physical bit storage cells (32 bytes x 8 bits)

    // ----------------------------------------------------------------
    // 3. Write 5:32 Decoder -> 256 Write Enable Lines
    // ----------------------------------------------------------------
    wire [31:0] wr_wordline = (cs && wen) ? (32'b1 << wr_addr) : 32'b0;
    wire        addr_ready_flag = |wr_wordline;

    // Expand 32 wordlines to 256 parallel bit enables (8 lines per slice)
    wire [255:0] wr_bit_enables;
    genvar w;
    generate
        for (w = 0; w < 32; w = w + 1) begin : gen_wr_enables
            assign wr_bit_enables[w*8 +: 8] = {8{wr_wordline[w]}};
        end
    endgenerate

    // ----------------------------------------------------------------
    // 4. Read 5:32 Decoder -> 256 Read Gating -> 8-Bit Read Bitline Bus
    // ----------------------------------------------------------------
    wire [31:0] rd_wordline = (cs && ren) ? (32'b1 << rd_sel) : 32'b0;

    // Expand 32 wordlines to 256 parallel read selects (8 lines per slice)
    wire [255:0] rd_bit_selects;
    genvar r;
    generate
        for (r = 0; r < 32; r = r + 1) begin : gen_rd_selects
            assign rd_bit_selects[r*8 +: 8] = {8{rd_wordline[r]}};
        end
    endgenerate

    // Gate each of the 256 bit-cells with its read select line
    wire [255:0] gated_mem_cells = mem_cells & rd_bit_selects;

    // Combine all 32 slices (0..7, 8..15, ..., 248..255) onto the shared 8-bit read bitlines
    reg [7:0] rd_bitline;
    integer b;
    always @(*) begin
        rd_bitline = 8'h00;
        for (b = 0; b < 32; b = b + 1) begin
            rd_bitline = rd_bitline | gated_mem_cells[b*8 +: 8];
        end
    end

    // ----------------------------------------------------------------
    // 5. Synchronous Execution Core
    // ----------------------------------------------------------------
    reg [7:0] full_assembled_byte;
    reg [7:0] full_encrypted_byte;
    integer bit_idx;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            msb_buf      <= 4'b0000;
            nibble_phase <= 1'b0;
            data_out     <= 8'h00;
            mem_cells    <= 256'b0;
        end else if (!cs) begin
            nibble_phase <= 1'b0;
            data_out     <= 8'h00;
        end else begin
            // --- Write Path: 2 Consecutive Clocks ---
            if (!wen) begin
                nibble_phase <= 1'b0;
            end else begin
                if (!nibble_phase) begin
                    // Clock 1: Latch 4-bit MSB into msb_buf
                    msb_buf      <= io_in;
                    nibble_phase <= 1'b1;

                    $display("\n[WRITE CYCLE 1: MSB]");
                    $display("  Incoming ui_in[3:0] : 4'b%04b", io_in);
                    $display("  Target Write Address: %0d", wr_addr);
                end else begin
                    // Clock 2: Assemble MSB + LSB into full 8-bit byte and encrypt
                    /* verilator lint_off BLKSEQ */
                    full_assembled_byte = {msb_buf, io_in};
                    full_encrypted_byte = full_assembled_byte ^ CIPHER_KEY;
                    /* verilator lint_on BLKSEQ */
                    
                    nibble_phase        <= 1'b0;
                   $display("\n[WRITE CYCLE 2: LSB & COMMIT TO 256-BIT MATRIX]");
                   $display("  Incoming ui_in[3:0] : 4'b%04b", io_in);
                   $display("  Buffered MSB        : 4'b%04b", msb_buf);
                   $display("  Assembled 8-Bit Data: 8'b%08b (0x%02X)", full_assembled_byte, full_assembled_byte);
                   $display("  XOR Encrypted Byte  : 8'b%08b (0x%02X)", full_encrypted_byte, full_encrypted_byte);

                    if (addr_ready_flag) begin
                        for (bit_idx = 0; bit_idx < 256; bit_idx = bit_idx + 1) begin
                            if (wr_bit_enables[bit_idx]) begin
                                Map bit_idx modulo 8 to drive 0..7, 8..15, ..., 248..255 correctly
                                mem_cells[bit_idx] <= full_encrypted_byte[bit_idx % 8];
                            end
                        end
                        $display("  [SUCCESS] Written into bit-slice [%0d:%0d] of 256-bit memory", 
                                 wr_addr*8 + 7, wr_addr*8);
                    end
                end
            end

            // --- Read Path: 1-Clock Parallel Decrypted Readout ---
            if (!ren) begin
                data_out <= 8'h00;
            end else begin
                // Decrypt from the 8-bit read bitlines onto dedicated data_out pins
                data_out <= rd_bitline ^ CIPHER_KEY;

                $display("\n[DECODER-DRIVEN READOUT]");
                $display("  Read Target Address   : %0d", rd_sel);
                $display("  Bit-Slice Selected    : [%0d:%0d]", rd_sel*8 + 7, rd_sel*8);
                $display("  Read Bitline Encrypted: 8'b%08b (0x%02X)", rd_bitline, rd_bitline);
                $display("  Decrypted data_out Bus  : 8'b%08b (0x%02X)", rd_bitline ^ CIPHER_KEY, rd_bitline ^ CIPHER_KEY);
            end
        end
    end
endmodule
