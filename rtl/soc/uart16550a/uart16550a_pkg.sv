package uart16550a_pkg;
    function automatic logic [4:0] calc_stop_ticks (
        input logic [1:0] word_len,
        input logic       stop_bits
    );
        if (stop_bits == 1'b0)      calc_stop_ticks = 5'd15;
        else if (word_len == 2'b00) calc_stop_ticks = 5'd23;
        else                        calc_stop_ticks = 5'd31;
    endfunction

    function automatic logic calc_parity (
        input logic [7:0] data,
        input logic [1:0] word_len,
        input logic       parity_even,
        input logic       parity_stick
    );
        logic [7:0] masked_data;
        logic       odd_ones;

        masked_data = data & (8'hFF >> (3 - word_len));
        odd_ones = ^masked_data;

        if (parity_stick) begin
            calc_parity = ~parity_even;
        end
        else begin
            calc_parity = parity_even ? odd_ones : ~odd_ones;
        end
    endfunction
endpackage
