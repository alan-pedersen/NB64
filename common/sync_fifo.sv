module sync_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
)(
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   push,
    input  logic                   pop,
    input  logic [WIDTH-1:0]       wdata,
    output logic [WIDTH-1:0]       rdata,
    output logic                   empty,
    output logic                   full,
    output logic [$clog2(DEPTH):0] fill_level
);
    localparam int INDEX_BITS = $clog2(DEPTH);

    logic [WIDTH-1:0] fifo [0:DEPTH-1];

    // Pointers (+1 bit for wrap-around logic when buffer is full)
    logic [INDEX_BITS:0] rd_ptr;
    logic [INDEX_BITS:0] wr_ptr;

    assign rdata = fifo[rd_ptr[INDEX_BITS-1:0]];

    assign empty = (rd_ptr == wr_ptr);
    assign full  = ((rd_ptr[INDEX_BITS] != wr_ptr[INDEX_BITS]) &&
                    (rd_ptr[INDEX_BITS-1:0] == wr_ptr[INDEX_BITS-1:0]));

    assign fill_level = wr_ptr - rd_ptr;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            wr_ptr <= 0;
        end
        else begin
            if (push && !full) begin
                fifo[wr_ptr[INDEX_BITS-1:0]] <= wdata;
                wr_ptr <= wr_ptr + 1;
            end

            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end
endmodule
