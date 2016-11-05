`default_nettype none

//
// Run sectest.
// See initest.src for sources.
//
module testbench();

// Global time parameters.
timeunit 1ns / 10ps;

// Inputs.
logic        clk, reset;
logic [63:0] i_data;
logic  [7:0] i_tag;

// Outputs.
logic [63:0] o_ad;                      // address/data output
logic  [7:0] o_tag;                     // tag output
logic        o_astb;                    // address strobe
logic        o_rd;                      // read op
logic        o_wr;                      // write op

// Instantiate CPU.
cpu cpu(clk, reset, i_data, i_tag,
    o_ad, o_tag, o_astb, o_rd, o_wr);

// Setup trace moninor.
tracer tr();
logic [19:0] waddr;                     // needed for tracer

//--------------------------------------------------------------
// Microinstruction ROM.
//
logic [111:0] memory[4096] = '{
    `include "../microcode/sectest.v"
    default: '0
};

string tracefile = "output.trace";
int limit;
int trace;                              // Trace level
int tracefd;                            // Trace file descriptor
time ctime;                             // Current time
logic [11:0] pc_x;                      // Current PC address at execution stage
logic [112:1] opcode_x;                 // Current opcode at execution stage

//
// Generate clock at 100MHz.
//
always #5 clk = ~clk;

//
// Main loop.
//
initial begin
    $display("");
    $display("--------------------------------");

    // Dump waveforms.
    if ($test$plusargs("dump")) begin
        $dumpfile("output.vcd");
        $dumpvars();
    end

    // Enable detailed instruction trace to file.
    trace = 2;
    $display("Generate trace file %0S", tracefile);
    tracefd = $fopen(tracefile, "w");

    // Limit the simulation by specified number of cycles.
    if (! $value$plusargs("limit=%d", limit)) begin
        // Default limit value.
        limit = 100000;
        $display("Limit: %0d", limit);
        $fdisplay(tracefd, "Limit: %0d", limit);
    end

    cpu.memory = memory;

    // Start with reset active
    clk = 1;
    reset = 1;

    // Hold reset for a while.
    #10 reset = 0;

    // Run until limit.
    #limit begin
        $display("\n----- Time Limit Exceeded -----");
        $fdisplay(tracefd, "\n----- Time Limit Exceeded -----");
        $finish(1);
    end
end

//
// Print a message to stdout and trace file
//
task message(input string msg);
    $display("*** %s", msg);
    $fdisplay(tracefd, "(%0d) *** %s", ctime, msg);
endtask

//
// Print message when test passes the label.
//
task check_pass(input int label, input string msg);
    logic  [3:0] sqi;
    logic [11:0] a;
    assign sqi = opcode_x[112:109];
    assign a   = opcode_x[108:97];

    // Look for CONT operation with given address
    if (sqi == 14 && a == label)
        message(msg);
endtask

//
// Check for a jump from label `from' to label `to'.
// When jump detected, consider the test passed and
// go instead to the target address.
//
task check_jump(
    input int label_from,
    input int label_to,
    input int target,
    input string msg
);
    if (pc_x == label_from && tr.pc_f == label_to) begin
        message(msg);
        tr.pc_x = target;
        cpu.control.uPC = target;
        cpu.opcode = cpu.memory[target];
        tr.opcode_x = cpu.opcode;
    end
endtask

//
// Addresses of sectest.
//
localparam LABEL_PSLO23 = 1;
localparam LABEL_PSLO24 = 9;
localparam LABEL_CLO24  = 12;
localparam LABEL_CLO25  = 28;
localparam LABEL_CMOD2  = 57;
localparam LABEL_CMOD3  = 68;
localparam LABEL_CMODA  = 116;
localparam LABEL_CMODB  = 125;
localparam LABEL_CMODC  = 134;
localparam LABEL_CMODD  = 144;
localparam LABEL_CMODE  = 154;
localparam LABEL_CMOD10 = 163;
localparam LABEL_CMOD11 = 172;
localparam LABEL_CMOD12 = 181;
localparam LABEL_CMOD13 = 191;
localparam LABEL_CMOD14 = 201;
localparam LABEL_CMOD16 = 244;
localparam LABEL_MC17   = 387;
localparam LABEL_MC18   = 407;
localparam LABEL_CMOD1A = 418;
localparam LABEL_CMOD1C = 427;
localparam LABEL_CMOD1E = 450;
localparam LABEL_CADR2  = 480;
localparam LABEL_CADR3  = 490;
localparam LABEL_CADR5  = 509;
localparam LABEL_CADR6  = 519;
localparam LABEL_CADR8  = 538;
localparam LABEL_CADR9  = 547;
localparam LABEL_CADRB  = 568;
localparam LABEL_CADRC  = 582;
localparam LABEL_CADRD  = 604;
localparam LABEL_CADRE  = 619;
localparam LABEL_CADRF  = 634;
localparam LABEL_CADR11 = 659;
localparam LABEL_CADR12 = 672;
localparam LABEL_CADR13 = 694;
localparam LABEL_CADR14 = 709;
localparam LABEL_CADR15 = 725;
localparam LABEL_CADR17 = 751;
localparam LABEL_CADR18 = 764;
localparam LABEL_CADR19 = 786;
localparam LABEL_CADR1A = 802;
localparam LABEL_CADR1B = 818;
localparam LABEL_CADR1D = 844;
localparam LABEL_CADR1E = 858;
localparam LABEL_CADR1F = 880;
localparam LABEL_CADR20 = 895;
localparam LABEL_CADR21 = 910;
localparam LABEL_CADR22 = 923;
localparam LABEL_CADR23 = 935;
localparam LABEL_CADR24 = 949;
localparam LABEL_CADR25 = 971;
localparam LABEL_CADR26 = 986;
localparam LABEL_CADR27 = 1001;
localparam LABEL_CAD2C  = 1014;
localparam LABEL_CAD2D  = 1042;
localparam LABEL_CTAG3  = 1102;
localparam LABEL_CBOI4  = 1123;
localparam LABEL_CBOI5  = 1147;
localparam LABEL_CA2    = 1174;
localparam LABEL_CA3    = 1184;
localparam LABEL_CICLA  = 1296;
localparam LABEL_CKLB   = 1309;
localparam LABEL_CKLC   = 1358;
localparam LABEL_CCD    = 1394;
localparam LABEL_CCE    = 1406;
localparam LABEL_CCF    = 1421;
localparam LABEL_CC10   = 1433;
localparam LABEL_CC11   = 1445;
localparam LABEL_CC12   = 1464;
localparam LABEL_CC13   = 1491;
localparam LABEL_CC14   = 1507;
localparam LABEL_CKL15  = 1514;
localparam LABEL_CKL16  = 1538;
localparam LABEL_CTWR   = 1564;
localparam LABEL_ERRTST = 1665;
localparam LABEL_ERRINF = 1667;
localparam LABEL_ERRINH = 1669;

//
// Test switcher.
//
initial begin
    forever begin
        // Wait for instruction, valid on leading edge of clk
        wait(clk);
        ctime = $time;
        pc_x = tr.pc_x;
        opcode_x = tr.opcode_x;

        // Wait until everything is stable
        wait(!clk);
        #1;

        // In case of failure, the tests stop at label ERR*
        if (pc_x == LABEL_ERRTST || pc_x == LABEL_ERRINF ||
            pc_x == LABEL_ERRINH) begin
            message("Test FAIL");
            $display("--------------------------------");
            $finish(1);
        end

        //
        // Skip CLO23 test
        //
        check_jump(LABEL_PSLO23-1, LABEL_PSLO23, LABEL_PSLO24-1, "Skip test CLO23");

        //
        // Big test
        //
        check_pass(LABEL_CLO24,  "Test CLO24 pass");
        check_pass(LABEL_CLO25,  "Test CLO25 pass");
        check_pass(LABEL_CMOD2,  "Test CMOD2 pass");
        check_pass(LABEL_CMOD3,  "Test CMOD3 pass");
        check_pass(LABEL_CMODA,  "Test CMODA pass");
        check_pass(LABEL_CMODB,  "Test CMODB pass");
        check_pass(LABEL_CMODC,  "Test CMODC pass");
        check_pass(LABEL_CMODD,  "Test CMODD pass");
        check_pass(LABEL_CMODE,  "Test CMODE pass");
        check_pass(LABEL_CMOD10, "Test CMOD10 pass");
        check_pass(LABEL_CMOD11, "Test CMOD11 pass");
        check_pass(LABEL_CMOD12, "Test CMOD12 pass");
        check_pass(LABEL_CMOD13, "Test CMOD13 pass");
        check_pass(LABEL_CMOD14, "Test CMOD14 pass");
        check_pass(LABEL_CMOD16, "Test CMOD16 pass");
        check_pass(LABEL_MC17,   "Test MC17 pass");
        check_pass(LABEL_MC18,   "Test MC18 pass");
        check_pass(LABEL_CMOD1A, "Test CMOD1A pass");
        check_pass(LABEL_CMOD1C, "Test CMOD1C pass");
        check_pass(LABEL_CMOD1E, "Test CMOD1E pass");
        check_pass(LABEL_CADR2,  "Test CADR2 pass");
        check_pass(LABEL_CADR3,  "Test CADR3 pass");
        check_pass(LABEL_CADR5,  "Test CADR5 pass");
        check_pass(LABEL_CADR6,  "Test CADR6 pass");
        check_pass(LABEL_CADR8,  "Test CADR8 pass");
        check_pass(LABEL_CADR9,  "Test CADR9 pass");
        check_pass(LABEL_CADRB,  "Test CADRB pass");
        check_pass(LABEL_CADRC,  "Test CADRC pass");
        check_pass(LABEL_CADRD,  "Test CADRD pass");
        check_pass(LABEL_CADRE,  "Test CADRE pass");
        check_pass(LABEL_CADRF,  "Test CADRF pass");
        check_pass(LABEL_CADR11, "Test CADR11 pass");
        check_pass(LABEL_CADR12, "Test CADR12 pass");
        check_pass(LABEL_CADR13, "Test CADR13 pass");
        check_pass(LABEL_CADR14, "Test CADR14 pass");
        check_pass(LABEL_CADR15, "Test CADR15 pass");
        check_pass(LABEL_CADR17, "Test CADR17 pass");
        check_pass(LABEL_CADR18, "Test CADR18 pass");
        check_pass(LABEL_CADR19, "Test CADR19 pass");
        check_pass(LABEL_CADR1A, "Test CADR1A pass");
        check_pass(LABEL_CADR1B, "Test CADR1B pass");
        check_pass(LABEL_CADR1D, "Test CADR1D pass");
        check_pass(LABEL_CADR1E, "Test CADR1E pass");
        check_pass(LABEL_CADR1F, "Test CADR1F pass");
        check_pass(LABEL_CADR20, "Test CADR20 pass");
        check_pass(LABEL_CADR21, "Test CADR21 pass");
        check_pass(LABEL_CADR23, "Test CADR23 pass");
        check_pass(LABEL_CADR24, "Test CADR24 pass");
        check_pass(LABEL_CADR25, "Test CADR25 pass");
        check_pass(LABEL_CADR26, "Test CADR26 pass");
        check_pass(LABEL_CADR27, "Test CADR27 pass");
        check_pass(LABEL_CAD2C,  "Test CAD2C pass");
        check_pass(LABEL_CAD2D,  "Test CAD2D pass");
        check_pass(LABEL_CTAG3,  "Test CTAG3 pass");
        check_pass(LABEL_CBOI4,  "Test CBOI4 pass");
        check_pass(LABEL_CBOI5,  "Test CBOI5 pass");
        check_pass(LABEL_CA2,    "Test CA2 pass");
        check_pass(LABEL_CA3,    "Test CA3 pass");
        check_pass(LABEL_CICLA,  "Test CICLA pass");
        check_pass(LABEL_CKLB,   "Test CKLB pass");
        check_pass(LABEL_CKLC,   "Test CKLC pass");
        check_pass(LABEL_CCD,    "Test CCD pass");
        check_pass(LABEL_CCE,    "Test CCE pass");
        check_pass(LABEL_CCF,    "Test CCF pass");
        check_pass(LABEL_CC10,   "Test CC10 pass");
        check_pass(LABEL_CC11,   "Test CC11 pass");
        check_pass(LABEL_CC12,   "Test CC12 pass");
        check_pass(LABEL_CC13,   "Test CC13 pass");
        check_pass(LABEL_CC14,   "Test CC14 pass");
        check_pass(LABEL_CKL15,  "Test CKL15 pass");
        check_pass(LABEL_CKL16,  "Test CKL16 pass");

        if (pc_x == LABEL_CTWR-1) begin
            message("Test PASS");
            $display("--------------------------------");
            $finish(0);
        end
    end
end

endmodule
