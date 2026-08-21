module nb64__rf_gpr #(
    parameter int XLEN = 64
)(
    input  logic            clk,
    
    input  logic [4:0]      raddr1,
    input  logic [4:0]      raddr2,
    output logic [XLEN-1:0] rdata1,
    output logic [XLEN-1:0] rdata2,

    input  logic            we,
    input  logic [4:0]      waddr,
    input  logic [XLEN-1:0] wdata
);
    logic [XLEN-1:0] regs [1:31];

    logic fwd_rs1;
    logic fwd_rs2;

    // 'waddr != 0' is technically redundant; if waddr == 0,
    // raddrX must also be 0, which is already caught by the
    // 'raddrX == 0' check.
    assign fwd_rs1 = we && (waddr != 0) && (waddr == raddr1);
    assign fwd_rs2 = we && (waddr != 0) && (waddr == raddr2);

    always_comb begin
        if (raddr1 == 0)  rdata1 = 0;
        else if (fwd_rs1) rdata1 = wdata;
        else              rdata1 = regs[raddr1];

        if (raddr2 == 0)  rdata2 = 0;
        else if (fwd_rs2) rdata2 = wdata;
        else              rdata2 = regs[raddr2];
    end

    // GPR state upon reset is undefined per RISC-V spec.
    // Also, omitting reset allows LUTRAM inference on FPGAs.
    always_ff @(posedge clk) begin
        if (we && (waddr != 0)) begin
            regs[waddr] <= wdata;
        end
    end
endmodule
