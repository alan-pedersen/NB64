module uart16550a_wb #(
    parameter int DW = 32
)(
    input  logic clk,
    input  logic rst,

    wb_if.slave  wb,

    input  logic rx,
    output logic tx,
    output logic intr
);
    logic       reg_en;
    logic       reg_wr;
    logic [2:0] reg_addr;
    logic [7:0] reg_wdata;
    logic [7:0] reg_rdata;

    assign reg_en    = wb_valid;
    assign reg_wr    = wb.we;
    assign reg_addr  = wb.addr[2:0];
    assign reg_wdata = wb.dat_w[7:0];

    uart16550a u_uart16550a (
        .clk       (clk),
        .rst       (rst),
        .reg_en    (reg_en),
        .reg_wr    (reg_wr),
        .reg_addr  (reg_addr),
        .reg_wdata (reg_wdata),
        .reg_rdata (reg_rdata),
        .rx        (rx),
        .tx        (tx),
        .intr      (intr)
    );

    logic ack_q;
    logic wb_valid;

    assign wb_valid  = wb.cyc & wb.stb & ~ack_q;
    assign wb.dat_r  = {{(DW-8){1'b0}}, reg_rdata};
    assign wb.ack    = ack_q;
    assign wb.err    = 0;

    always_ff @(posedge clk) begin
        if (rst) begin
            ack_q <= 0;
        end
        else begin
            if (wb_valid) ack_q <= 1;
            else          ack_q <= 0;
        end
    end
endmodule
