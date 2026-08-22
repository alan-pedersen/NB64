module nb64__exu_alu import nb64_pkg::*; #(
    parameter int XLEN = 64
)(
    input  alu_op_t         alu_op,
    input  logic [XLEN-1:0] src_a,
    input  logic [XLEN-1:0] src_b,
    output logic [XLEN-1:0] result
);
    logic            is_word;
    logic            is_alt;

    logic [5:0]      shamt;
    logic [XLEN-1:0] shift_src;
    logic [XLEN-1:0] base_result;

    assign is_alt  = alu_op[3];
    assign is_word = alu_op[4];

    always_comb begin
        if (is_word) begin
            shamt     = {1'b0, src_b[4:0]};
            shift_src = {{(XLEN-32){is_alt & src_a[31]}}, src_a[31:0]};
        end
        else begin
            shamt     = src_b[5:0];
            shift_src = src_a;
        end
    end

    always_comb begin
        unique case (alu_op)
            ALU_ADD,
            ALU_SUB,
            ALU_ADDW,
            ALU_SUBW: base_result = is_alt ? (src_a - src_b) : (src_a + src_b);

            ALU_SLL,
            ALU_SLLW: base_result = shift_src << shamt;

            ALU_SRL,
            ALU_SRLW: base_result = shift_src >> shamt;

            ALU_SRA,
            ALU_SRAW: base_result = $signed(shift_src) >>> shamt;

            ALU_SLT:  base_result = {{(XLEN-1){1'b0}}, ($signed(src_a) < $signed(src_b))};
            ALU_SLTU: base_result = {{(XLEN-1){1'b0}}, (src_a < src_b)};

            ALU_AND:  base_result = src_a & src_b;
            ALU_OR:   base_result = src_a | src_b;
            ALU_XOR:  base_result = src_a ^ src_b;
            default:  base_result = 0;
        endcase
    end

    always_comb begin
        if (is_word) result = {{(XLEN-32){base_result[31]}}, base_result[31:0]};
        else         result = base_result;
    end
endmodule
