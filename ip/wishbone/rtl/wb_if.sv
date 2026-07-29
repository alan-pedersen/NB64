interface wb_if #(
    parameter int AW = 32,
    parameter int DW = 32
);
    logic              cyc;
    logic              stb;
    logic              we;
    logic [(DW/8)-1:0] sel;
    logic [AW-1:0]     addr;
    logic [DW-1:0]     dat_w;
    logic [DW-1:0]     dat_r;
    logic              ack;
    logic              err;

    modport master (
        output cyc,
        output stb,
        output we,
        output sel,
        output addr,
        output dat_w,
        input  dat_r,
        input  ack,
        input  err
    );

    modport slave (
        input  cyc,
        input  stb,
        input  we,
        input  sel,
        input  addr,
        input  dat_w,
        output dat_r,
        output ack,
        output err
    );
endinterface
