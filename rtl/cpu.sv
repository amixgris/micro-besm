// Instruction fields
logic SQI[3:0], A[11:0], МАР[1:0], ALU, ALUD[2:0], FUNC[2:0], ALUS[2:0],
      Н, RВ[3:0], RА[3:0], CI[1:0], SHMUX[3:0], SТОРС[5:0], MOD, PSHF[6:0],
      MNSA[1:0], MODNM[4:0], DSRC[3:0], YDST[3:0], SHF[1:0], ARBI[3:0],
      RLD, LЕТС, CYSTR[2:0], SCI, ICI, IСС, ISE, СЕМ, CEN, CSM, WЕМ,
      ЕСВ, WRB, BRA[1:0], ЕСА, WRA, ARA[1:0], YDEV[2:0], WRY, DDEV[2:0],
      WRD, IОМР, FFCNT[4:0], MPADR[3:0], COND[4:0], MPS;

//--------------------------------------------------------------
// Microinstruction control unit.
//
// БИС СУАМ вырабатывает сигналы /VЕ, /МЕ, /РЕ, которые
// используются для выборки внешних источников, подключенных к
// шине D:
//  * преобразователь начального адреса команд RMOD,WMOD и обращений
//    ПП (при наличии признака MOD, сигнал /МЕ);
//  * дополнительный преобразователь адреса, задающий адреса векторов
//    прерывания. А также знаков сомножителей для коррекции
//    поизведения (VE). (сигнал /РЕ не используется).
//
// Каждой микрокомандой вырабатывается только один сигнал
// разрешения для внешнего источника.
//
// Сигналы I0-I3 поступают из микропрограммы; /RLD - с дешифратора
// триггеров признаков; /СС - с мультиплексора условий; выходы
// У0-У11 передают полученный адрес микрокоманды; на вход CI в
// зависимости от 36 разряда МП подается либо “1”, либо прямой или
// инверсный выход с мультиплексора условий, либо “0” в момент
// входа в микропрограмму обработки прерываний; сигнал /CCEN
// всегда равен “0”.

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

am2910 control(clk, control_I, 0, control_nCC, control_nRLD, control_CI, 0,
    control_D, control_Y, , control_nVE, control_nME, control_nFULL);

assign control_I    = SQI;      // Four-bit instruction
assign control_nCC  = cond_mux; // Conditional Code Bit TODO
assign control_nRLD = RLD;      // Unconditional load bit for register/counter

// Carry-in bit for microprogram counter
assign control_CI = SCI ? 1 :
                    irq ? 0 :
                    ICI ? ~cond_mux : cond_mux;

// 12-bit data input
assign control_D = !control_nME & MOD ? pna_mod :   //TODO
                   !control_nVE       ? pna_irq;    //TODO

//--------------------------------------------------------------
// Microinstruction ROM.
//
logic [111:0] memory[4096] = '{
    `include "../microcode/microcode.v"
    default: '0
};
logic [112:1] opcode;               // 112-bit registered opcode

always @(posedge clk)
    opcode <= memory[control_Y];

//
// Microinstruction fields.
//
assign SQI   = opcode[112:109]; // Код операции селектора адреса микропрограмм СУАМ
assign A     = opcode[108:97];  // Адрес следующей микрокоманды или адрес ПЗУ констант
assign МАР   = opcode[96:95];   // Выбор источника адреса, поступающего на вход D СУАМ
assign ALU   = opcode[94];      // Разрешение выдачи информации из МПС на шину Y
assign ALUD  = opcode[93:91];   // Управление приемниками результата АЛУ
assign FUNC  = opcode[90:88];   // Код операции АЛУ МПС
assign ALUS  = opcode[87:85];   // Управление источниками операндов на входы АЛУ
assign Н     = opcode[84];      // Управление разрядностью АЛУ
assign RВ    = opcode[83:80];   // Адрес регистра канала B МПС
assign RА    = opcode[79:76];   // Адрес регистра канала A МПС
assign CI    = opcode[75:74];   // Управление переносом C0 АЛУ МПС, разряды I12-I11
assign SHMUX = opcode[73:70];   // Сдвиг в МПС, разряды I9-I6 КОП СУСС
assign SТОРС = opcode[69:64];   // Разряды I5-I0 КОП СУСС
assign MOD   = opcode[63];      // Привилегированный режим обращения к специальным регистрам
assign PSHF  = opcode[62:56];   // Параметр сдвига сдвигателя
assign MNSA  = opcode[62:61];   // Адрес источника номера модификатора
assign MODNM = opcode[60:56];   // Номер модификатора в группе регистров
assign DSRC  = opcode[55:52];   // Управление источниками информации на шину D
assign YDST  = opcode[51:48];   // Управление приемниками информации с шины Y ЦП
assign SHF   = opcode[47:46];   // Код операции сдвигателя
assign ARBI  = opcode[45:42];   // Код операции арбитра общей шины
assign RLD   = opcode[41];      // Загрузка регистра селектора адреса СУАМ и ШФ шин У ЦП и D СУАМ
assign LЕТС  = opcode[40];      // Прохождением признака ПИА на вход ПНА команд
assign CYSTR = opcode[39:37];   // Длительность тактового импульса
assign SCI   = opcode[36];      // Передача условия на вход инкрементора
assign ICI   = opcode[35];      // Инверсия условия на вход инкрементора (CI) СУАМ
assign IСС   = opcode[34];      // Инверсия условий, выбираемых полем COND
assign ISE   = opcode[33];      // Разрешение внешних и внутренних прерываний
assign СЕМ   = opcode[32];      // Разрешение записи в машинный регистр состояния М СУСС
assign CEN   = opcode[31];      // Разрешение записи в микромашинный регистр состояния N СУСС
assign CSM   = opcode[30];      // Управление обращением к ОЗУ модификаторов
assign WЕМ   = opcode[29];      // Разрешение записи в ОЗУ модификаторов
assign ЕСВ   = opcode[28];      // Выбор канал а B БОИ данных
assign WRB   = opcode[27];      // Запись по каналу B в БОИ данных и БОИ тега
assign BRA   = opcode[26:25];   // Адрес регистра канала B БОИ даннных и БОИ тега
assign ЕСА   = opcode[24];      // Выбор канала A БОИ данных
assign WRA   = opcode[23];      // Запись по каналу A в БОИ данных.
assign ARA   = opcode[22:21];   // Адрес регистра канала A БОИ даннных
assign YDEV  = opcode[20:18];   // Выбор источника или приемника информации с шины Y
assign WRY   = opcode[17];      // Запись в источники или приемники шины Y
assign DDEV  = opcode[16:14];   // Выбор источника или приемника информации с шины D
assign WRD   = opcode[13];      // Управление записью в источники или приемники шины D
assign IОМР  = opcode[12];      // Выбор дешифратора триггеров признаков или часов и таймера
assign FFCNT = opcode[11:7];    // Установка/сброс триггеров признаков
assign MPADR = opcode[10:7];    // Адрес регистра в блоке обмена с ПП
assign COND  = opcode[6:2];     // Выбор условия, подлежащего проверке
assign MPS   = opcode[1];       // Выбор источника параметра сдвига

//--------------------------------------------------------------
datapath alu(
    // Signals for am2901
    input               clk,        // Clock
    input         [8:0] alu_I,      // ALU instruction, from ALUD, FUNC and ALUS
    input         [3:0] alu_A,      // A register address, from RA
    input         [3:0] alu_B,      // B register address, from RB
    input        [63:0] alu_D,      // D bus input
    input               alu_C0,     // Carry input, from CI
    input               alu_mode32  // 32-bit mode flag, from H
    output logic [63:0] alu_oYalu,  // Y bus output from ALU

    // Signals for am2904
    input         [9:0] ss_I,       // Status/Shift instruction, from SHMUX and STOPC
    input               ss_nCEM,    // Machine status register enable, from CEM
    input               ss_nCEN,    // Micro status register enable, from CEN
    output logic  [3:0] ss_oY,      // Y bus output from Status/Shift
    output logic        ss_CT,      // Conditional test output
    output logic        ss_C        // Carry multiplexer output
);
// ALU:
// ALUS -> I[2:0]
// FUNC -> I[5:3]
// ALUD -> I[8:6]
// RA -> A
// RB -> B
// H  -> mode32
// CI -> I[12:11]
// ? -> C0

// Status/Shifts:
// SHMUX -> I[9:6]
// STOPC -> I[5:0]
// CEM   -> ~nCEM
// CEN   -> ~nCEN

//--------------------------------------------------------------
extbus boi(
    input        [71:0] DA,     // A data bus input...
    output logic [71:0] oDA,    // ...and output
    input        [71:0] DB,     // B data bus input...
    output logic [71:0] oDB,    // ...and output
    input        [71:0] DC,     // C data bus input...
    output logic [71:0] oDC,    // ...and output
    input        [71:0] DX,     // X data bus input...
    output logic [71:0] oDX,    // ...and output

    input         [1:0] AA,     // A address input
    input         [1:0] AB,     // B address input
    input         [1:0] AC,     // C address input
    input         [1:0] AX,     // X address input

    input               ECA,    // A port enable
    input               ECB,    // B port enable
    input               ECC,    // C port enable
    input               ECX,    // X port enable

    input               WA,     // A write enable
    input               WB,     // B write enable
    input               WC,     // C write enable
    input               WX      // X write enable
);

arbiter arb(
    //TODO
);
