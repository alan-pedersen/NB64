module uart_16550a_wb #(
    parameter int DW = 32
)(
    input  logic clk,
    input  logic rst,

    wb_if.slave  wb,

    input  logic rx,
    output logic tx,
    output logic irq
);
    logic       csr_en;
    logic       csr_wr;
    logic [2:0] csr_addr;
    logic [7:0] csr_wdata;
    logic [7:0] csr_rdata;

    assign csr_en    = wb_valid;
    assign csr_wr    = wb.we;
    assign csr_addr  = wb.addr[2:0];
    assign csr_wdata = wb.dat_w[7:0];

    uart_16550a u_uart_16550a (
        .clk       (clk),
        .rst       (rst),
        .csr_en    (csr_en),
        .csr_wr    (csr_wr),
        .csr_addr  (csr_addr),
        .csr_wdata (csr_wdata),
        .csr_rdata (csr_rdata),
        .rx        (rx),
        .tx        (tx),
        .irq       (irq)
    );

    logic ack_q;
    logic wb_valid;

    assign wb_valid  = wb.cyc & wb.stb & ~ack_q;
    assign wb.dat_r  = {{(DW-8){1'b0}}, csr_rdata};
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
