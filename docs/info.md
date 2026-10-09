<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works
Architecture Overview:The project implements a secure QSPI SRAM Architecture as a Single-Module ASIC featuring a 256-pin Joint Connection Matrix and a 32times 8-bit SRAM core.
section 1: (Control Pins, Ingestion & 8-Bit XOR Engine): Handles input signals (clks, active-low reset rst_n, enables en[1:0], and 4-bit data inputs in[3:0]), buffering them through buffer and phase tagging before passing them to an 8-bit XOR encryption engine using key to produce encrypted data 8 pins (0:7).  
Section 2: (Decoder & Bit Enable): Features a 5:32 write decoder taking address inputs(a0 to a4) to generate 32 word lines and 256 pin outputs that bridge directly to the SRAM core via the 256-pin joint connection.  
Section 3: (Read 5:32 Decoder & Bitlines): Manages read operations using a read decoder (5:32) and 256 read selects, passing data through an XOR decryption block to generate an 8-bit parallel output (8'b1100_0011/0xC3).  
Clock Timing: Write operations take 2 clock cycles, while read operations take 1 clock cycle, controlled via synchronous clock inputs and an active-low reset (rst_n). 

## How to test
Reset & Clock Setup: Initialize the system by asserting the active-low reset (rst_n) and supplying stable clock signals (clk).  
Executing a Write Cycle (2 Clock Cycles): Provide the 4-bit data  (in[3:0]) and address lines (ai[3:0]). The data is encrypted via the 8-bit XOR engine and routed through the 256-pin joint matrix into the designated SRAM storage byte (e.g., Rows 0 to 31).  
Executing a Read Cycle (1 Clock Cycle): Assert the read control signals (ctrl_sel1, read enable) and target the desired memory row using the read 5:32 decoder. The retrieved bitlines are decrypted using the XOR decryption unit and verified at the 8-bit parallel output (out[7:0]).  

## External hardware


