`default_nettype none

`define TODO 'z

//
// Micro-BESM processor
//
module cpu(
    input  wire         clk,        // Clock
    input  wire         reset,      // Global reset
    input  wire  [63:0] i_data,     // data bus input
    input  wire   [7:0] i_tag,      // tag bus input
    output logic [63:0] o_ad,       // address/data output
    output logic  [7:0] o_tag,      // tag output
    output logic        o_astb,     // address strobe
    output logic        o_rd,       // read op
    output logic        o_wr        // write op
);
timeunit 1ns / 10ps;

// Internal registers
logic  [4:0] MODGN;             // РНГ: регистр номера группы памяти модификаторов
logic  [7:0] PROCN;             // РНП: регистр номера процесса
logic [31:0] RR;                // регистр режимов и триггеры признаков
logic  [9:0] PHYSPG;            // РФС: регистр физической страницы
logic [31:0] UREG;              // регистр исполнительного адреса (запись)
logic [63:0] sh_out;            // результат сдвига
logic [10:0] PSHIFT;            // регистр параметра сдвига (только запись)
logic        CCLR;              // запуск сброса кэша
logic  [7:0] instr_code;        // код операции команды
logic [19:0] instr_addr;        // адресная часть команды
logic [11:0] jump_addr;         // ПНА КОП основного или дополнительного формата

//TODO:
logic  [6:0] LOS;               // результат поиска левой единицы
logic [11:0] grp_addr;          // ПНА групп

// Signals for ALU
logic  [8:0] alu_I;             // ALU instruction, from ALUD, FUNC and ALUS
logic  [3:0] alu_A;             // A register address, from RA
logic  [3:0] alu_B;             // B register address, from RB
logic [63:0] alu_D;             // D bus input
logic        alu_C0;            // Carry input
logic        alu_mode64;        // 64-bit mode flag, from H

logic [63:0] alu_Y;             // Y bus output from ALU

// Signals for status/shift unit
logic [12:0] ss_I;              // Status/Shift instruction, from SHMUX and STOPC
logic        ss_nCEM;           // Machine status register enable, from CEM
logic        ss_nCEN;           // Micro status register enable, from CEN

logic  [3:0] ss_Y;              // Y bus input
logic  [3:0] ss_oY;             // Y bus output from Status/Shift
logic        ss_CT;             // Conditional test output

// Global data bus Y
logic [63:0] Y;

logic stopm0, stopm1;           // Флаги останова

// Память обмена с пультовым процессором
logic [7:0] mpmem[16];

// Память приписок страниц
logic [19:0] psmem[1024];

// Мультиплексор условий
logic condition, condmux;

// Биты регистра режимов (РР)
logic [2:0] grp;
logic normb, rndb, ovrib, bnb, ovrftb, drg, rcb, cb, cemlrg, intstp, tr0, tr1;
logic flag_v, flag_c, flag_n, flag_z, no_badop;
logic no_rtag, no_badacc, no_progtag, no_intr, no_wtag, single_step, no_wprot;
logic no_rprot, flag_negaddr, no_procnm, no_paging, flag_jump;
logic [1:0] rr_unused;

logic besm6_mode;               // режим эмуляции (РЭ)
logic instr_ir15;               // stack mode flag
logic tkk;                      // признак правой команды стандартизатора (TKK)

// Signals for arbiter
logic  [3:0] arb_req;           // код операции арбитра
logic        arb_rdy;           // ответ арбитра

// External bus interface
// Inputs
logic [71:0] bus_DA, bus_DB;    // A, B data inputs
logic [71:0] bus_DX;            // X data bus
logic  [1:0] bus_ARX;           // X address input
logic        bus_ECBTAG;        // B tag port enable
logic        bus_ECX;           // X port enable
logic        bus_WRX;           // X write enable

// Outputs
logic [71:0] bus_oDA, bus_oDB;  // A, B data outputs TODO
logic [71:0] bus_oDC;           // C data output
logic [71:0] bus_oDX;           // X data output

// Control unit
// Input signals
logic  [3:0] control_I;         // Four-bit instruction
logic        control_nCC;       // Conditional Code Bit
logic        control_nRLD;      // Unconditional load bit for register/counter
logic        control_CI;        // Carry-in bit for microprogram counter
logic [11:0] control_D;         // 12-bit data input to chip

// Output signals
logic [11:0] control_Y;         // 12-bit address output
logic        control_nVE;       // Vector output enable
logic        control_nME;       // Mapping PROM output enable
logic        control_nFULL;     // Stack full flag

//--------------------------------------------------------------
// Microinstruction ROM.
//
logic [111:0] memory[4096] = '{
    `include "../microcode/microcode.v"
    default: '0
};

logic [112:1] opcode;           // 112-bit latched opcode

always @(posedge clk)
    if (reset) begin
        opcode <= '0;           // Reset state
        besm6_mode <= 0;        // Изначально РЭ=0
    end else
        opcode <= memory[control_Y];

// Microinstruction fields.
wire  [3:0] SQI   = opcode[112:109]; // Код операции селектора адреса микропрограмм СУАМ
wire [11:0] A     = opcode[108:97];  // Адрес следующей микрокоманды или адрес ПЗУ констант
wire  [1:0] MAP   = opcode[96:95];   // Выбор источника адреса, поступающего на вход D СУАМ
wire        ALU   = opcode[94];      // Разрешение выдачи информации из МПС на шину Y
wire  [2:0] ALUD  = opcode[93:91];   // Управление приемниками результата АЛУ
wire  [2:0] FUNC  = opcode[90:88];   // Код операции АЛУ МПС
wire  [2:0] ALUS  = opcode[87:85];   // Управление источниками операндов на входы АЛУ
wire        H     = opcode[84];      // Управление разрядностью АЛУ
wire  [3:0] RB    = opcode[83:80];   // Адрес регистра канала B МПС
wire  [3:0] RA    = opcode[79:76];   // Адрес регистра канала A МПС
wire  [1:0] CI    = opcode[75:74];   // Управление переносом C0 АЛУ МПС, разряды I12-I11
wire  [3:0] SHMUX = opcode[73:70];   // Сдвиг в МПС, разряды I9-I6 КОП СУСС
wire  [5:0] STOPC = opcode[69:64];   // Разряды I5-I0 КОП СУСС
wire        MOD   = opcode[63];      // Привилегированный режим обращения к специальным регистрам
wire  [6:0] PSHF  = opcode[62:56];   // Параметр сдвига сдвигателя
wire  [1:0] MNSA  = opcode[62:61];   // Адрес источника номера модификатора
wire  [4:0] MODNM = opcode[60:56];   // Номер модификатора в группе регистров
wire  [3:0] DSRC  = opcode[55:52];   // Управление источниками информации на шину D
wire  [3:0] YDST  = opcode[51:48];   // Управление приемниками информации с шины Y ЦП
wire  [1:0] sh_op = opcode[47:46];   // Код операции сдвигателя: CYCL, LOG, ARIPH или EMULF
wire  [3:0] ARBI  = opcode[45:42];   // Код операции арбитра общей шины
wire        RLD   = opcode[41];      // Загрузка регистра селектора адреса СУАМ и ШФ шин Y ЦП и D СУАМ
wire        LETC  = opcode[40];      // Прохождение признака ПИА на вход ПНА команд
wire  [2:0] CYSTR = opcode[39:37];   // Длительность тактового импульса
wire        SCI   = opcode[36];      // Передача условия на вход инкрементора
wire        ICI   = opcode[35];      // Инверсия условия на вход инкрементора (CI) СУАМ
wire        ICC   = opcode[34];      // Инверсия условий, выбираемых полем COND
wire        ISE   = opcode[33];      // Разрешение внешних и внутренних прерываний
wire        CEM   = opcode[32];      // Разрешение записи в машинный регистр состояния M CYCC
wire        CEN   = opcode[31];      // Разрешение записи в микромашинный регистр состояния N CYCC
wire        CSM   = opcode[30];      // Управление обращением к памяти модификаторов
wire        WEM   = opcode[29];      // Разрешение записи в память модификаторов
wire        ECB   = opcode[28];      // Выбор канала B БОИ данных
wire        WRB   = opcode[27];      // Запись по каналу B в БОИ данных и БОИ тега
wire  [1:0] BRA   = opcode[26:25];   // Адрес регистра канала B БОИ даннных и БОИ тега
wire        ECA   = opcode[24];      // Выбор канала A БОИ данных
wire        WRA   = opcode[23];      // Запись по каналу A в БОИ данных.
wire  [1:0] ARA   = opcode[22:21];   // Адрес регистра канала A БОИ даннных
wire  [2:0] YDEV  = opcode[20:18];   // Выбор источника или приемника информации с шины Y
wire        WRY   = opcode[17];      // Запись в источники или приемники шины Y
wire  [2:0] DDEV  = opcode[16:14];   // Выбор источника или приемника информации с шины D
wire        WRD   = opcode[13];      // Управление записью в источники или приемники шины D
wire        IOMP  = opcode[12];      // Выбор дешифратора триггеров признаков или часов и таймера
wire  [4:0] FFCNT = opcode[11:7];    // Установка/сброс триггеров признаков
wire  [3:0] MPADR = opcode[10:7];    // Адрес регистра в блоке обмена с ПП
wire  [4:0] COND  = opcode[6:2];     // Выбор условия, подлежащего проверке
wire        MPS   = opcode[1];       // Выбор источника параметра сдвига

//--------------------------------------------------------------
// Microinstruction control unit.
//
// БИС СУАМ вырабатывает сигналы /VE, /ME, /PE, которые
// используются для выборки внешних источников, подключенных к
// шине D:
//  * преобразователь начального адреса команд RMOD,WMOD и обращений
//    ПП (при наличии признака MOD, сигнал /ME);
//  * дополнительный преобразователь адреса, задающий адреса векторов
//    прерывания. A также знаков сомножителей для коррекции
//    поизведения (VE). (сигнал /PE не используется).
//
// Каждой микрокомандой вырабатывается только один сигнал
// разрешения для внешнего источника.
//
// Сигналы I0-I3 поступают из микропрограммы; /RLD - с дешифратора
// триггеров признаков; /CC - с мультиплексора условий; выходы
// Y0-Y11 передают полученный адрес микрокоманды; на вход CI в
// зависимости от 36 разряда МП подается либо “1”, либо прямой или
// инверсный выход с мультиплексора условий, либо “0” в момент
// входа в микропрограмму обработки прерываний; сигнал /CCEN
// всегда равен “0”.

am2910 control(clk,
    control_I, '0, control_nCC, control_nRLD, control_CI, '0,
    control_D, control_Y, , control_nVE, control_nME, control_nFULL);

assign control_I    = SQI;      // Four-bit instruction
assign control_nRLD = ~RLD;     // Unconditional load bit for register/counter

// Carry-in bit for microprogram counter
assign control_CI = (SCI ? condition : '1) ^ ICI;

// 12-bit data input
assign control_D =
    (MAP == 0) ? A :            // PE, конвейерный регистр
    (MAP == 1) ? jump_addr :    // ME, ПНА КОП основного или дополнительного формата
    (MAP == 2) ? grp_addr :     // GRP, ПНА групп и микропрограммные признаки "След0" И "След1"
                 alu_Y[11:0];   // Выход АЛУ

//TODO:
//assign control_D = !control_nME & MOD ? pna_mod :
//                   !control_nVE       ? pna_irq : x;

assign control_nCC = condition;

assign condition = ICC ? condmux : ~condmux;

// Выбор условия, подлежащего проверке.
always_comb case (COND)
      0: condmux = 1;           // YES, "да"
      1: condmux = normb;       // NORMB, блокировка нормализации (БНОР)
      2: condmux = rndb;        // RNDB, блокировка округления (БОКР)
      3: condmux = ovrib;       // OVRIB, блокировка прерывания по переполнению (БПП)
      4: condmux = bnb;         // BNB, блокировка выхода числа за диапазон БЭСМ-6 (ББЧ)
      5: condmux = ovrftb;      // OVRFTB, блокировка проверки переполнения поля упрятывания (БППУ)
      6: condmux = drg;         // DRG, режим диспетчера (РД)
      7: condmux = besm6_mode;  // EMLRG, режим эмуляции
      8: condmux = rcb;         // RCB, признак правой команды (ППК)
      9: condmux = cb;          // CB, признак изменения адреса 16 регистром (ПИА)
     10: condmux = cemlrg;      // CEMLRG, РЭС, 20-й разряд PP (резерв)
     11: condmux = ss_CT;       // CT, сигнал CT CYCC
     12: condmux = tr1;         // TR1, След1
     13: condmux = intstp;      // INTSTP, признак останова по прерыванию (ПОП)
     14: condmux = instr_ir15;  // IR15, стековый режим команды (ИР15)
     15: condmux = tkk;         // TKK, признак правой команды стандартизатора (TKK)
     16: condmux = `TODO;       // RUN, "пуск" от ПП
     17: condmux = `TODO;       // NMLRDY, отсутствие готовности умножителя
     19: condmux = `TODO;       // INT, признак наличия прерываний
     20: condmux = `TODO;       // FULMEM, память БМСП заполнена единицами
     21: condmux = arb_rdy;     // ARBRDY, готовность арбитра
     22: condmux = tr0;         // TR0, След0
     23: condmux = `TODO;       // CPMP, память обмена "ЦП -> ПП" свободна
default: condmux = 1;
endcase

//--------------------------------------------------------------
// Constant ROM.
//
logic [63:0] const_ROM[512] = '{
    `include "../microcode/constants.v"
    default: '0
};
logic [63:0] PROM;              // ПЗУ констант

assign PROM = const_ROM[A[8:0]];

//--------------------------------------------------------------
// Datapath: register file, ALU and status/shifts
//
datapath alu(clk,
    alu_I, alu_A, alu_B, alu_D, alu_C0, alu_mode64, alu_Y,
    ss_I, ss_nCEM, ss_nCEN, ss_Y, ss_oY, ss_CT);

assign alu_I = {ALUD, FUNC, ALUS};
assign alu_A = RA;
assign alu_B = RB;
assign alu_mode64 = H;
assign alu_C0 = condition;

// Управление источниками информации на шину D.
assign alu_D =
    (DSRC == 1)  ? {MODGN, 5'd0} :  // регистр номера группы памяти модификаторов
    (DSRC == 2)  ? PROCN :          // регистр номера процесса
    (DSRC == 3)  ? RR :             // регистр режимов и триггеры признаков
    (DSRC == 4)  ? {PHYSPG, 11'd0} : // регистр физической страницы
    (DSRC == 5)  ? arb_req :        // регистр КОП арбитра
    (DSRC == 8)  ? instr_addr :     // COMA, адресная часть команды
    (DSRC == 9)  ? sh_out :         // результат сдвига
    (DSRC == 10) ? instr_code :     // OPC, код операции команды
    (DSRC == 11) ? LOS :            // результат поиска левой единицы
    (DSRC == 12) ? PROM :           // ПЗУ констант
    (DDEV == 5)  ? {ss_oY, 6'd0} :  // STATUS, Y bus output from Status/Shift
                   instr_addr;      // источник не указан: адресная часть команды?

assign Y =
    (YDEV == 1 & !WRB) ? bus_oDB[71:64] :       // ECBTAG, канал В БОИ тега
    (YDEV == 2 & !WRY) ? `TODO :                // PHYSAD, физический адрес (только на чтение);
    (YDEV == 3 & !WRY) ? UREG :                 // RADRR, регистр исполнительного адреса (чтение);
    (YDEV == 4 & !WRY) ? psmem[UREG[19:10]] :   // PSMEM, память приписок (CS);
    (YDEV == 5 & !WRY) ? mpmem[MPADR] :         // МРМЕМ, память обмена с ПП;
                   ALU ? alu_Y :                // Y bus output from ALU
                         '0;

// Управление приемниками информации с шины Y ЦП.
always @(posedge clk)
    case (YDST)
     1: MODGN  <= Y[9:5];       // регистр номера группы памяти модификаторов
     2: PROCN  <= Y[7:0];       // регистр номера процесса
   /*3: RR     <= Y[31:0];*/    // регистр режимов и триггеры признаков
     4: PHYSPG <= Y[20:11];     // регистр физической страницы
   /*5: ARBOPC <= Y[3:0];*/     // код операции арбитра
     8: UREG   <= Y[31:0];      // ADRREG, регистр исполнительного адреса (запись)
   /*9: PSHIFT <= Y[10:0];*/    // регистр параметра сдвига (только запись)
    endcase

// Запись в источники или приемники шины Y.
always @(posedge clk)
    if (WRY)
        case (YDEV)
        4: psmem[UREG[19:10]] <= Y[19:0];   // PSMEM, память приписок (CS)
        5: mpmem[MPADR] <= Y[7:0];          // МРМЕМ, память обмена с ПП
        6: stopm0 <= Y[0];                  // STOPM0, флаг останова 0
        7: stopm1 <= Y[0];                  // STOPM1, флаг останова 1
        endcase

assign CCLR = (YDST == 10);     // запуск сброса кэша

assign ss_I = {CI, alu_I[7], SHMUX, STOPC};
assign ss_nCEM = !CEM;
assign ss_nCEN = !CEN;
assign ss_Y = Y[9:6];           // status bits: Z N C V

//--------------------------------------------------------------
// Shifter.
//
shifter sh(Y, PSHF, PSHIFT, sh_op, sh_out);

always @(posedge clk)
    if (YDST == 9)
        PSHIFT <= Y[10:0];
    else if (PSHF != 64)
        PSHIFT <= '0;

//--------------------------------------------------------------
// Modifier memory.
//
logic [3:0] instr_reg;          // поле модификатора команды
logic [31:0] irmem[1024];       // память регистров-модификаторов
logic [4:0] mn;                 // номер модификатора

assign mn =
    (MNSA == 0) ? UREG[3:0] :   // U, регистр исполнительного адреса
    (MNSA == 1) ? instr_reg :   // IRA, поле модификатора команды
    (MNSA == 3) ? ~MODNM :      // MP, поле MODNM микрокоманды
                  '0;           // не используется

always @(posedge clk)
    if (CSM & WEM) begin
        irmem[{MODGN, mn}] <= Y[31:0];
    end

//--------------------------------------------------------------
// External bus interface
//
assign bus_ECBTAG = (YDEV == 1);    // ydev=ECBTAG, выбор регистров БОИ тега

assign bus_DA = alu_D;
assign bus_DB = {Y[7:0], Y};
assign bus_DX = {i_tag, i_data};
assign o_ad   = bus_oDX[63:0];
assign o_tag  = bus_oDX[71:64];

extbus busio(
    bus_DA, bus_oDA,                    // A data bus
    bus_DB, bus_oDB,                    // B data bus
    72'b00, bus_oDC,                    // C data bus
    bus_DX, bus_oDX,                    // X data bus
    ARA, BRA,          2'b01, bus_ARX,  // address inputs
    ECA, ECB, bus_ECBTAG, '1, bus_ECX,  // port enable
    WRA, WRB,             '0, bus_WRX   // write enable
);

//--------------------------------------------------------------
// Arbiter
//
arbiter arb(clk,
    arb_req,                            // input request
    bus_ARX, bus_ECX, bus_WRX,          // X bus control
    o_astb, o_rd, o_wr,                 // external memory interface
    arb_rdy                             // resulting status
);

always @(posedge clk)                   // arbiter request
    if (arb_rdy)
        arb_req <= '0;                  // clear request when ready
    else if (YDST == 5)
        arb_req <= Y[3:0];              // set from Y data bus
    else if (ARBI != 0)
        arb_req <= ARBI;                // set from microinstruction

//--------------------------------------------------------------
// Instruction decoder
//
logic instr_ext;                // extended opcode flag
logic uflag;                    // признак изменения адресом (ПИА)
assign uflag = LETC & cb;

decoder dec(
    bus_oDC[63:0],              // instruction word
    besm6_mode,                 // besm6 compatibility (РЭ)
    tkk,                        // right half flag (ТКК)
    instr_reg,                  // modifier index
    instr_code,                 // instruction code (КОП)
    instr_ext,                  // extended opcode flag
    instr_ir15,                 // stack mode flag
    instr_addr                  // address
);

logic [11:0] optab[4096] = '{
    `include "../microcode/optab.v"
    default: '0
};
assign jump_addr = optab[{instr_ext, besm6_mode, instr_ir15, uflag, instr_code}];

//--------------------------------------------------------------
// Mode register (РР)
//
assign RR = {       // регистр режимов (РР)
    rr_unused,      // РР.31-30 - not specified
    flag_jump,      // РР.29 - признак команды передачи управления (ППУ)
    rcb,            // РР.28 - RCB, признак правой команды (ППК)
    cb,             // РР.27 - CB, признак изменения адреса 16 регистром (ПИА)
    no_paging,      // РР.26 - блокировка приписки (БП)
    no_procnm,      // РР.25 - блокировка проверки номера процесса (БПНП)
    flag_negaddr,   // РР.24 - режим отрицательных адресов (РОА)
    no_rprot,       // РР.23 - блокировка защиты страниц по обращению (БЗО)
    no_wprot,       // РР.22 - блокировка защиты страниц по записи (БЗЗ)
    intstp,         // РР.21 - признак останова по прерыванию (ПОП)
    single_step,    // РР.20 - режим пошагового выполнения команд (РШ)
    cemlrg,         // РР.19 - CEMLRG, РЭС, 20-й разряд PP (резерв)
    no_wtag,        // РР.18 - блокировка проверки тега при записи (БПТЗ)
    no_intr,        // РР.17 - блокировка внешних прерываний (БВП)
    no_progtag,     // РР.16 - блокировка программной интерпретации тега (БПИНТ)
    no_badacc,      // РР.15 - блокировка реакции на чужой сумматор (БЧС)
    no_rtag,        // РР.14 - блокир.проверки тега при чтении операнда (БПТЧ)
    no_badop,       // РР.13 - блокировка реакции на чужой операнд (БЧОП)
    drg,            // РР.12 - DRG, режим диспетчера (РД)
    ovrftb,         // РР.11 - OVRFTB, блокировка проверки переполнения поля упрятывания (БППУ)
    bnb,            // РР.10 - BNB, блокировка выхода числа за диапазон БЭСМ-6 (ББЧ)
    flag_z,         // РР.9 - признак нуля (ПН или Z)
    flag_n,         // РР.8 - признак знака (ПЗ или N)
    flag_c,         // РР.7 - признак переноса (ППС или С)
    flag_v,         // РР.6 - признак переполнения (ПП или OVR)
    ovrib,          // РР.5 - OVRIB, блокировка прерывания при переполнении (БПП)
    grp,            // РР.4-2 - группа для условных переходов (ГС,ГУ,ГЛ)
    rndb,           // РР.1 - RNDB, блокировка округления (БОКР)
    normb           // РР.0 - NORMB, блокировка нормализации (БНОР)
};
always @(posedge clk)
    if (YDST == 3) begin
        rr_unused    <= Y[31:30];
        flag_jump    <= Y[29];
        rcb          <= Y[28];
        cb           <= Y[27];
        no_paging    <= Y[26];
        no_procnm    <= Y[25];
        flag_negaddr <= Y[24];
        no_rprot     <= Y[23];
        no_wprot     <= Y[22];
        intstp       <= Y[21];
        single_step  <= Y[20];
        cemlrg       <= Y[19];
        no_wtag      <= Y[18];
        no_intr      <= Y[17];
        no_progtag   <= Y[16];
        no_badacc    <= Y[15];
        no_rtag      <= Y[14];
        no_badop     <= Y[13];
        drg          <= Y[12];
        ovrftb       <= Y[11];
        bnb          <= Y[10];
        flag_z       <= Y[9];
        flag_n       <= Y[8];
        flag_c       <= Y[7];
        flag_v       <= Y[6];
        ovrib        <= Y[5];
        grp          <= Y[4:2];
        rndb         <= Y[1];
        normb        <= Y[0];
    end

// Установка/сброс триггеров признаков.
// Управляющие сигналы А1, А0 для обращения к часам и таймеру.
always @(posedge clk)
    if (! IOMP) case (FFCNT)
     1: grp <= 3'b001;      // LOGGRP, установка логической группы
     2: grp <= 3'b010;      // MULGRP, установка группы умножения
     3: grp <= 3'b100;      // ADDGRP, установка группы сложения
   /*5: cb <= '1;*/         // SЕТС, установка триггера ПИА
   /*6: rcb <= '0;*/        // CLRRCB, сброс триггера ППК
   /*7: rcb <= '1;*/        // SETRCB, установка триггера ППК
     8: flag_jump <= '0;    // CLRJMP, сброс триггера ППУ
     9: flag_jump <= '1;    // SETJMP, установка триггера ППУ
    10: no_intr <= '0;      // SETEI, сброс маски прерываний (разрешение прерываний)
    11: no_intr <= '1;      // CLREI, установка маски прерываний (запрет прерываний)
    12: tr0 <= '0;          // CLRTR0, сброс микропрограммного признака "След0"
    13: tr0 <= '1;          // SETTR0, установка мп признака "След0"
    14: tr1 <= '0;          // CLRTR1, сброс мп признака "След1"
    15: tr1 <= '1;          // SETTR1, установка мп признака "След1"
    16: /*TODO <= '0*/;     // CLRCT, сброс прерывания от часов счетного времени
    17: /*TODO <= '0*/;     // CLRCTT, сброс прерывания от таймера счетного времени
    18: tkk <= '0;          // CLRTKK, сброс триггера коммутации команд - ТКК (ППК стандартизатора)
    19: tkk <= '1;          // SЕТТКК, установка ТКК
    20: besm6_mode <= '0;   // SETNR, установка НР
    21: /*TODO <= '1*/;     // STRTLD, запуск загрузки ОЗУ БМСП единицами
    22: besm6_mode <= '1;   // SETER, установка РЭ
    23: tkk <= ~tkk;        // СНТКК, переброс ТКК (работает в счетном режиме!)
    24: /*TODO <= '1*/;     // SETHLT, установка триггера "Останов" (Halt)
    25: /*TODO <= '0*/;     // CLRINT, сброс прерываний (кроме прерываний от таймеров)
    26: /*TODO <= '0*/;     // CLRRUN, сброс триггера "Пуск"
    27: /*TODO <= '1*/;     // RDMPCP, установка признака "ОЗУ обмена ПП -> ЦП прочитано"
    28: /*TODO <= '1*/;     // LDMPCP, установка признака "в ОЗУ обмена ПП -> ЦП есть информация"
    29: /*TODO <= '1*/;     // LDCPMP, установка признака "в ОЗУ обмена ЦП -> ПП есть информация"
    30: /*TODO <= '1*/;     // PRGINT, установка программного прерывания с номером 31
    31: /*TODO <= '1*/;     // EXTINT, установка внешнего прерывания на магистраль
    endcase

// Признак изменения адресом (ПИА) устанавливается и сбрасывается разными путями
always @(posedge clk)
    if (DDEV == 3)
        cb <= '0;           // CLRCD, сброс ПИА, дополнительный сигнал
    else if (!IOMP & FFCNT == 5)
        cb <= '1;           // SЕТС, установка триггера ПИА

always @(posedge clk)
    if (ISE)
        rcb <= tkk;         // Копирование ТКК в ППК
    else if (!IOMP)
        case (FFCNT)
          6: rcb <= '0;     // CLRRCB, сброс триггера ППК
          7: rcb <= '1;     // SETRCB, установка триггера ППК
        endcase

endmodule
