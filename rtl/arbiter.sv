`default_nettype none

//
// External bus arbiter for micro-BESM
//
module arbiter(
    input  wire        clk,
    input  wire  [3:0] request, // input request

    output logic [1:0] arx,     // busio register index
    output logic       ecx,     // busio port enable
    output logic       wrx,     // busio write enable
    output logic       astb,    // memory address strobe
    output logic       rd,      // memory read
    output logic       wr,      // memory write
    output logic       done     // resulting acknowledge
);
timeunit 1ns / 10ps;

logic [6:0] step;

parameter MAXSTATE = 'h7f;

typedef enum bit [1:0] {
    ADDR  = 'b00,   // RG0 - физический адрес
    CMD   = 'b01,   // RG1 - регистр левой, правой команды
    WDATA = 'b10,   // RG2 - регистр операнда
    RDATA = 'b11    // RG3 - регистр результата
} reg_index;

//
// Sequential state transition
//
always_ff @(posedge clk)
    if (request == 0)
        step <= 0;
    else if (!done & step != MAXSTATE)  // TODO need some action on timeout
        step <= step + 1;

//
// Output assignments
//
always_comb begin
    // Done by default
    {arx, ecx, wrx, astb, rd, wr, done} = {RDATA, '0, '0, '0, '0, '0, '1};

    case (request)
    0:  // Reset everything
        {arx, ecx, wrx, astb, rd, wr, done} = {RDATA, '0, '0, '0, '0, '0, '0};

    1:  // CCRD, чтение кэша команд
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=CCRD not implemented yet!", $time);
        endcase

    2:  // CCWR, запись в кэш команд
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=CCWR not implemented yet!", $time);
        endcase

    3:  // DCRD, чтение кэш операндов
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=DCRD not implemented yet!", $time);
        endcase

    4:  // DCWR, запись в кэш операндов
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=DCWR not implemented yet!", $time);
        endcase

    8:  // FЕТСН, чтение команды
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=FETCH not implemented yet!", $time);
        endcase

    9:  // DRD, чтение операнда
        case (step)
                0:  // Send address
                    {arx, ecx, wrx, astb, rd, wr, done} = {ADDR,  '1, '0, '1, '0, '0, '0};
                1:  // Read word
                    {arx, ecx, wrx, astb, rd, wr, done} = {RDATA, '1, '1, '0, '1, '0, '0};
                2:  // Done
                    {arx, ecx, wrx, astb, rd, wr, done} = {RDATA, '0, '0, '0, '0, '0, '1};
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=DRD not implemented yet!", $time);
        endcase

    10: // DWR, запись результата
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=DWR not implemented yet!", $time);
        endcase

    11: // RDMWR, чтение - модификация - запись (семафорная)
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=RDMWR not implemented yet!", $time);
        endcase

    12: // BTRWR, запись в режиме блочной передачи
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=BTRWR not implemented yet!", $time);
        endcase

    13: // BTRRD, чтение в режиме блочной передачи
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=BTRRD not implemented yet!", $time);
        endcase

    14: // BICLR, сброс прерываний на шине
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=BICLR not implemented yet!", $time);
        endcase

    15: // BIRD, чтение прерываний с шины
        case (step)
              //0: //TODO
              //1: //TODO
              //2: //TODO
        default: if (testbench.tracefd)
                    $fdisplay(testbench.tracefd, "(%0d) *** Arbiter op=BIRD not implemented yet!", $time);
        endcase

    default: begin
            //TODO: Unknown request
            if (request & testbench.tracefd)
                $fdisplay(testbench.tracefd, "(%0d) *** Wrong arbiter op=%0d!", $time, request);
        end
    endcase
end

endmodule
