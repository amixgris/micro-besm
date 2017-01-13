//
// Top level module for the CPU simulation.
//
// This is not a synthesizable code, but a part of verification testbench.
//
// Copyright (c) 2016 Serge Vakulenko
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
`default_nettype none

module testbench();

// Global time parameters.
timeunit 1ns / 10ps;

// Inputs.
logic        clk, reset;
logic [63:0] i_data;                    // data input
logic  [7:0] i_tag;                     // tag input
logic        i_irq;                     // interrupt request

// Outputs.
logic [63:0] o_ad;                      // address/data output
logic  [7:0] o_tag;                     // tag output
logic        o_astb;                    // address strobe
logic        o_rd;                      // read op
logic        o_wr;                      // write op
logic        o_wforce;                  // ignore write protection
logic        o_iack;                    // interrupt acknowledge
logic [63:0] ram_data;                  // data output from RAM
logic [63:0] irq_pending;               // mask of pending interrupts

// Instantiate CPU.
cpu cpu(clk, reset, i_data, i_tag,
    o_ad, o_tag, o_astb, o_rd, o_wr, o_wforce,
    i_irq, o_iack);

// Setup trace moninor.
tracer tr();

// 1Mword x 64bit of tagged RAM.
tmemory ram(clk, o_ad, o_tag,
    o_astb, o_rd, o_wr, o_wforce,
    ram_data, i_tag);

// Interrupt processing.
assign i_data = o_iack ? irq_pending : ram_data;

always @(posedge clk)
    if (o_iack)
        i_irq = '0;                     // deactivate interrupt request

string tracefile = "output.trace";
string hexfile;                         // Input hex file with code
int limit;
int trace;                              // Trace level
int tracefd;                            // Trace file descriptor

//
// Generate clock 500MHz.
//
always #1 clk = ~clk;

//
// Main loop.
//
initial begin
    // Print help message, if +trace option not specified.
    $display("");
    if (! $value$plusargs("trace=%d", trace)) begin
        $display("----- Trace option required -----");
        $display("Options:");
        $display("    +trace=0          No tracing");
        $display("    +trace=1          Trace instructions and registers to file %s", tracefile);
        $display("    +trace=2          Trace micro-instructions");
        $display("    +hex=NAME         Load code into main memory");
        $display("    +limit=NUM        Limit execution to a number of cycles (default %0d)", limit);
        $display("    +clearmem         Initialize all memory to zero");
        $display("    +dump             Dump waveforms as output.vcd");
        $display("");
        $finish(1);
    end
    $display("--------------------------------");

    // Dump waveforms.
    if ($test$plusargs("dump")) begin
        $dumpfile("output.vcd");
        $dumpvars();
    end

    // Enable instruction trace to file.
    if (trace) begin
        $display("Generate trace file %0S", tracefile);
        tracefd = $fopen(tracefile, "w");
    end

    // Clear all RAM.
    if ($test$plusargs("clearmem")) begin
        for (int i=0; i<1024*1024; i+=1) begin
            ram.mem[i] = '0;
            ram.tag[i] = 'h34;
        end
        if (trace)
            $fdisplay(tracefd, "Clear all memory");
    end

    // Load program code into main memory.
    if ($value$plusargs("hex=%s", hexfile)) begin
        load_hex();
    end

    // Limit the simulation by specified number of cycles.
    if (! $value$plusargs("limit=%d", limit)) begin
        // Default limit value.
        limit = 100000;
        $display("Limit: %0d", limit);
        if (trace)
            $fdisplay(tracefd, "Limit: %0d", limit);
    end

    // Start with reset active
    clk = 1;
    reset = 1;
    i_irq = 0;
    irq_pending = '0;

    // Hold reset for a while.
    #2 reset = 0;

    // Run until limit.
    tr.start();
    #limit tr.terminate("Time Limit Exceeded");
end

//
// Latch phys addresses for tracer
//
logic [19:0] fetch_paddr;               // physical address of last fetch
logic [19:0] mem_paddr;                 // physical address of last load/store
logic [19:0] mem_vaddr;                 // virtual address of last load/store

always @(cpu.o_rd, cpu.o_wr)
    if (cpu.o_wr)
        mem_paddr = ram.waddr;
    else if (cpu.o_rd) begin
        if (cpu.arb_opc == 8)
            fetch_paddr = ram.waddr;
        else
            mem_paddr = ram.waddr;
    end

always @(cpu.o_astb)
    if (cpu.o_astb)
        mem_vaddr <= cpu.mode_besm6 ? cpu.vaddr[14:0]
                                    : cpu.vaddr[19:0];

//
// Detect HLT instruction
//
always @(posedge clk) begin
    if (!cpu.mode_besm6 &&              // Native mode
        !cpu.instr_ext &&               // Base instruction format
        cpu.instr_code == 'hff)         // HLT opcode
        tr.cpu_halted();
end

//
// Hack for instrset test.
//
always @(posedge clk) begin
    logic [19:0] pc;

    assign pc = {
        cpu.alu.p19_16.ram[3], cpu.alu.p15_12.ram[3],
        cpu.alu.p11_8.ram[3],  cpu.alu.p7_4.ram[3],
        cpu.alu.p3_0.ram[3] };

    if (pc == 'h808c6 && cpu.mr_mem[32+7] == 'h03bf) begin
        cpu.mr_mem[32+7] = 0;
        if (trace)
            $fdisplay(tracefd, "(%0d) *** Clear M7[1] to speed up memory initialization",
                $time);
    end
end

//
// Load program code, optional.
//
task load_hex();
    int fd, i, count;
    string line;
    logic [63:0] word;
    logic [7:0] tag;

    // Open file with code.
    fd = $fopen(hexfile, "r");
    if (fd == 0) begin
        $error("%s: Cannot open", hexfile);
        $finish(1);
    end

    // Read hex code.
    count = 0;
    while ($fgets(line, fd)) begin
        if (line[0] == "#")
            continue;

        if ($sscanf(line, "%x %x %x", i, tag, word) == 3) begin
            //$fdisplay(tracefd, "%05x: %02x %016x", i, tag, word);
            ram.mem[i] = word;
            ram.tag[i] = tag;
            count += 1;
        end
    end
    $fclose(fd);
    $display("Load %0d words from %s", count, hexfile);
    if (trace)
        $fdisplay(tracefd, "Load %0d words from %s", count, hexfile);
endtask

endmodule
