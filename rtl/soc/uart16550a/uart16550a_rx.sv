module uart16550a_rx (
    input  logic        clk,
    input  logic        rst,
    input  logic [15:0] baud_div,
    input  logic        rx,
    output logic [7:0]  rx_data,
    output logic        rx_valid,
    output logic        rx_pe,
    output logic        rx_fe,
    output logic        rx_bi,

    input  logic [1:0]  lcr_word_len,
    input  logic        lcr_parity_en,
    input  logic        lcr_parity_even,
    input  logic        lcr_parity_stick
);
    import uart16550a_pkg::*;

    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        START  = 3'd1,
        DATA   = 3'd2,
        PARITY = 3'd3,
        STOP   = 3'd4
    } state_t;

    state_t      state;

    logic        rx_meta;
    logic        rx_sync;
    logic        rx_prev;

    logic [15:0] baud_div_q;
    logic [15:0] baud_counter;
    logic        baud_tick_16x;

    logic [7:0]  rsr;
    logic [3:0]  max_bits; // +1 bit
    logic [3:0]  bit_cnt;  // +1 bit
    logic [4:0]  counter;  // Can reduce one bit since only to 16
    logic        parity_expected;
    logic        parity_received;

    logic        is_zero_data;
    logic        is_zero_parity;
    logic        break_condition;

    logic        midpoint_pe;
    logic        midpoint_fe;
    logic        midpoint_bi;

    assign is_zero_data    = (rsr == 8'd0);
    assign is_zero_parity  = (!lcr_parity_en || (parity_received == 1'b0));
    assign break_condition = is_zero_data && is_zero_parity;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1;
            rx_sync <= 1;
            rx_prev <= 1;
        end
        else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

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
            baud_div_q      <= 0;
            rsr             <= 0;
            max_bits        <= 0;
            bit_cnt         <= 0;
            counter         <= 0;
            parity_expected <= 0;
            parity_received <= 0;
            midpoint_pe     <= 0;
            midpoint_fe     <= 0;
            midpoint_bi     <= 0;
            rx_data         <= 0;
            rx_valid        <= 0;
            rx_pe           <= 0;
            rx_fe           <= 0;
            rx_bi           <= 0;
            state           <= IDLE;
        end
        else begin
            rx_valid <= 0;
            rx_pe    <= 0;
            rx_fe    <= 0;
            rx_bi    <= 0;

            unique case (state)
                IDLE: begin
                    if ((rx_sync == 0) && (rx_prev == 1)) begin
                        baud_div_q  <= baud_div;
                        rsr         <= 0;
                        max_bits    <= 4 + {2'b00, lcr_word_len}; // inconsistent with N-1 coding style ?? IGNORE
                        bit_cnt     <= 0;
                        counter     <= 0;
                        midpoint_pe <= 0;
                        midpoint_fe <= 0;
                        midpoint_bi <= 0;
                        state       <= START;
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

                            if ((counter == 7) && (rx_sync != 0)) begin
                                state <= IDLE;
                            end
                        end
                    end
                end
                DATA: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter <= 0;

                            if (bit_cnt > max_bits) begin
                                parity_expected <= calc_parity(rsr, lcr_word_len, lcr_parity_even, lcr_parity_stick);
                                state           <= lcr_parity_en ? PARITY : STOP;
                            end
                        end
                        else begin
                            counter <= counter + 1;

                            if (counter == 7) begin
                                rsr[bit_cnt[2:0]] <= rx_sync;
                                bit_cnt           <= bit_cnt + 1;
                            end
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

                            if (counter == 7) begin
                                parity_received <= rx_sync;

                                if (rx_sync != parity_expected) begin
                                    midpoint_pe <= 1;
                                end
                            end
                        end
                    end
                end
                STOP: begin
                    if (baud_tick_16x) begin
                        if (counter == 15) begin
                            counter  <= 0;
                            rx_valid <= 1;
                            rx_data  <= rsr;
                            rx_pe    <= midpoint_pe;
                            rx_fe    <= midpoint_fe;
                            rx_bi    <= midpoint_bi;
                            state    <= IDLE;
                        end
                        else begin
                            counter <= counter + 1;

                            if (counter == 7) begin
                                if (rx_sync != 1) begin
                                    midpoint_fe <= 1;

                                    if (break_condition) begin
                                        midpoint_bi <= 1;
                                    end
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule
