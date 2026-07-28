module uart16550a_tx (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] baud_div,
    input  logic        tx_start,
    input  logic [7:0]  tx_data,
    output logic        tx_ready,
    output logic        tx,

    input  logic [1:0]  lcr_word_len,
    input  logic        lcr_stop_bits,
    input  logic        lcr_parity_en,
    input  logic        lcr_parity_even,
    input  logic        lcr_parity_stick,
    input  logic        lcr_break_en,
    output logic        tsr_empty
);
    import uart16550a_pkg::*;

    typedef enum logic [2:0] {
        IDLE     = 3'd0,
        START    = 3'd1,
        DATA     = 3'd2,
        PARITY   = 3'd3,
        STOP     = 3'd4
    } state_t;

    state_t      state;

    logic [15:0] baud_div_q;
    logic [15:0] baud_counter;
    logic        baud_tick_16x;

    logic [7:0]  tsr;        // Transmit Shift Register
    logic [2:0]  max_bits;   // Number of bits per character minus 1
    logic [2:0]  bit_cnt;    // Counter to track the character bits transmitted
    logic [4:0]  stop_ticks; // Number of baud ticks for the STOP phase
    logic [4:0]  counter;    // Counter to track TX sampling ticks and STOP phase ticks
    logic        parity;     // The computed parity bit

    always_ff @(posedge clk) begin
        if (rst || (state == IDLE) || (baud_div_q == 0)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 0;
        end
        else if (baud_counter == (baud_div_q - 1)) begin
            baud_counter  <= 0;
            baud_tick_16x <= 1;
        end
        else begin
            baud_counter  <= baud_counter + 1;
            baud_tick_16x <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            tx <= 1;
        end
        else if (lcr_break_en) begin
            tx <= 0;
        end
        else begin
            unique case (state)
                IDLE:   tx <= 1;
                START:  tx <= 0;
                DATA:   tx <= tsr[0];
                PARITY: tx <= parity;
                STOP:   tx <= 1;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            baud_div_q <= 0;
            tsr        <= 0;
            max_bits   <= 0;
            bit_cnt    <= 0;
            stop_ticks <= 0;
            counter    <= 0;
            parity     <= 0;
            tx_ready   <= 1;
            tsr_empty  <= 1;
            state      <= IDLE;
        end
        else begin
            unique case (state)
                IDLE: begin
                    if (tx_ready && tx_start) begin
                        baud_div_q <= baud_div;
                        tsr        <= tx_data;
                        max_bits   <= 4 + {1'b0, lcr_word_len};
                        bit_cnt    <= 0;
                        stop_ticks <= calc_stop_ticks(lcr_word_len, lcr_stop_bits);
                        counter    <= 0;
                        parity     <= calc_parity(tx_data, lcr_word_len, lcr_parity_even, lcr_parity_stick);
                        tx_ready   <= 0;
                        tsr_empty  <= 0;
                        state      <= START;
                    end
                end
                START: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= DATA;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                DATA: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            tsr     <= (tsr >> 1);
                            bit_cnt <= bit_cnt + 1;

                            if (bit_cnt == max_bits) begin
                                state <= lcr_parity_en ? PARITY : STOP;
                            end
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                PARITY: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;
                            state   <= STOP;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
                STOP: begin
                    if (baud_tick_16x) begin
                        if (counter == stop_ticks) begin
                            counter   <= 0;
                            tx_ready  <= 1;
                            tsr_empty <= 1;
                            state     <= IDLE;
                        end
                        else begin
                            counter <= counter + 1;
                        end
                    end
                end
            endcase
        end
    end
endmodule
