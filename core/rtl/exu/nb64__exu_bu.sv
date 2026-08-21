module nb64__exu_bu #(
    parameter int XLEN = 64
)(
    input logic [2:0]       br_type,
    input logic             is_branch,
    input logic             is_jump,
    input logic             is_jalr,

    input logic [XLEN-1:0]  rs1,
    input logic [XLEN-1:0]  rs2,
    input logic [XLEN-1:0]  pc,
    input logic [XLEN-1:0]  imm,

    output logic            pc_redirect,
    output logic [XLEN-1:0] pc_target
);
    localparam logic [2:0] BR_EQ  = 3'b000;
    localparam logic [2:0] BR_NE  = 3'b001;
    localparam logic [2:0] BR_LTS = 3'b100;
    localparam logic [2:0] BR_GES = 3'b101;
    localparam logic [2:0] BR_LTU = 3'b110;
    localparam logic [2:0] BR_GEU = 3'b111;

    logic            is_eq;
    logic            is_ltu;
    logic            is_lts;
    logic            branch_cond;

    logic [XLEN-1:0] bta_target;
    logic [XLEN-1:0] agu_target;

    assign is_eq  = (rs1 == rs2);
    assign is_ltu = (rs1 < rs2);
    assign is_lts = ($signed(rs1) < $signed(rs2));

    always_comb begin
        unique case (br_type)
            BR_EQ:   branch_cond = is_eq;
            BR_NE:   branch_cond = ~is_eq;
            BR_LTU:  branch_cond = is_ltu;
            BR_GEU:  branch_cond = ~is_ltu;
            BR_LTS:  branch_cond = is_lts;
            BR_GES:  branch_cond = ~is_lts;
            default: branch_cond = 0;
        endcase
    end

    assign bta_target = pc + imm;
    assign agu_target = (rs1 + imm) & ~XLEN'(1);

    assign pc_redirect = is_jump || (is_branch && branch_cond);
    assign pc_target   = is_jalr ? agu_target : bta_target;
endmodule
