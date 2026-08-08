module uart_16550a (
    input  logic       clk,
    input  logic       rst,

    input  logic       csr_en,
    input  logic       csr_wr,
    input  logic [2:0] csr_addr,
    input  logic [7:0] csr_wdata,
    output logic [7:0] csr_rdata,

    input  logic       rx,
    output logic       tx,
    output logic       irq
);
    import uart_16550a_pkg::*;

    logic csr_re;
    logic csr_we;

    assign csr_re = csr_en && !csr_wr;
    assign csr_we = csr_en && csr_wr;

    // === 16550A Registers === //

    logic [7:0]  dll;
    logic [7:0]  dlm;
    logic [7:0]  fcr;
    logic [7:0]  lcr;
    logic [7:0]  mcr;
    logic [7:0]  ier;
    logic [7:0]  lsr;
    logic [7:0]  msr;
    logic [7:0]  iir;
    logic [7:0]  scr;

    logic [15:0] baud_div;

    logic        fcr_write;
    logic        lsr_read;
    logic        iir_read;
    logic        fifo_en_toggle;

    assign baud_div       = {dlm, dll};
    assign fcr_write      = csr_we && (csr_addr == CSR_FCR);
    assign lsr_read       = csr_re && (csr_addr == CSR_LSR);
    assign iir_read       = csr_re && (csr_addr == CSR_IIR);
    assign fifo_en_toggle = fcr_write && (csr_wdata[0] != fcr[0]);

    // === RX Engine === //

    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        rx_pe;
    logic        rx_fe;
    logic        rx_bi;

    logic        rx_fifo_rst;
    logic        rx_fifo_push;
    logic        rx_fifo_pop;
    logic [10:0] rx_fifo_wdata;
    logic [10:0] rx_fifo_rdata;
    logic        rx_fifo_empty;
    logic        rx_fifo_full;
    logic [4:0]  rx_fifo_count;

    logic        rx_fifo_successful_push;
    logic        rx_fifo_successful_pop;

    logic [4:0]  rx_fifo_trigger_threshold;
    logic        rx_fifo_trigger_met;

    logic        rx_fifo_push_err;
    logic        rx_fifo_pop_err;
    logic        rx_fifo_err_present;
    logic [4:0]  rx_fifo_err_count;

    logic        rx_fifo_effective_full;
    logic        rx_fifo_overrun_event;
    logic        rx_fifo_head_update;
    logic        rx_fifo_head_has_err;
    logic        rx_fifo_head_err_cleared;
    logic        rx_fifo_pending_err;

    assign rx_fifo_rst              = rst || fifo_en_toggle || (fcr_write && csr_wdata[1]);
    assign rx_fifo_push             = rx_valid;
    assign rx_fifo_pop              = csr_re && !lcr[7] && (csr_addr == CSR_RBR);
    assign rx_fifo_wdata            = {rx_bi, rx_fe, rx_pe, rx_data};
    assign rx_fifo_successful_pop   = rx_fifo_pop && !rx_fifo_empty;
    assign rx_fifo_successful_push  = rx_fifo_push && !rx_fifo_effective_full;
    assign rx_fifo_effective_full   = fcr[0] ? rx_fifo_full : !rx_fifo_empty;
    assign rx_fifo_overrun_event    = rx_fifo_push && rx_fifo_effective_full;
    assign rx_fifo_head_update      = (rx_fifo_pop && !rx_fifo_empty) || (rx_fifo_push && rx_fifo_empty); // Push on empty or pop on not empty
    assign rx_fifo_head_has_err     = !rx_fifo_empty && |rx_fifo_rdata[10:8];
    assign rx_fifo_head_err_cleared = rx_fifo_head_has_err && lsr_err_ack;
    assign rx_fifo_pending_err      = (rx_fifo_err_count > 1) || (rx_fifo_err_count == 1 && !rx_fifo_head_err_cleared);
    assign rx_fifo_trigger_met      = (rx_fifo_count >= rx_fifo_trigger_threshold);
    assign rx_fifo_push_err         = rx_fifo_push && !rx_fifo_effective_full && |rx_fifo_wdata[10:8];
    assign rx_fifo_pop_err          = rx_fifo_pop && !rx_fifo_empty && |rx_fifo_rdata[10:8];
    assign rx_fifo_err_present      = (rx_fifo_err_count != 0);

    always_comb begin
        unique case (fcr[7:6])
            2'b00: rx_fifo_trigger_threshold = 1;
            2'b01: rx_fifo_trigger_threshold = 4;
            2'b10: rx_fifo_trigger_threshold = 8;
            2'b11: rx_fifo_trigger_threshold = 14;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rx_fifo_rst) begin
            rx_fifo_err_count <= 0;
        end
        else if (rx_fifo_push_err && !rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count + 1;
        end
        else if (!rx_fifo_push_err && rx_fifo_pop_err) begin
            rx_fifo_err_count <= rx_fifo_err_count - 1;
        end
    end

    uart_16550a_rx uart_rx (
        .clk              (clk),
        .rst              (rst),
        .baud_div         (baud_div),
        .rx               (rx),
        .rx_data          (rx_data),
        .rx_valid         (rx_valid),
        .rx_pe            (rx_pe),
        .rx_fe            (rx_fe),
        .rx_bi            (rx_bi),
        .lcr_word_len     (lcr[1:0]),
        .lcr_parity_en    (lcr[3]),
        .lcr_parity_even  (lcr[4]),
        .lcr_parity_stick (lcr[5])
    );

    sync_fifo #(
        .WIDTH (11),
        .DEPTH (16)
    ) rx_fifo (
        .clk   (clk),
        .rst   (rx_fifo_rst),
        .push  (rx_fifo_push),
        .pop   (rx_fifo_pop),
        .wdata (rx_fifo_wdata),
        .rdata (rx_fifo_rdata),
        .empty (rx_fifo_empty),
        .full  (rx_fifo_full),
        .count (rx_fifo_count)
    );

    // === TX Engine === //

    logic       tx_fifo_rst;
    logic       tx_fifo_push;
    logic       tx_fifo_pop;
    logic [7:0] tx_fifo_wdata;
    logic [7:0] tx_fifo_rdata;
    logic       tx_fifo_empty;
    logic       tx_fifo_full;

    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx_ready;
    logic       tsr_empty;

    // (fcr[0] || tx_fifo_empty) ensures that when FIFO mode is disabled, not more than
    // one push to the FIFO takes place.

    assign tx_fifo_rst   = rst || fifo_en_toggle || (fcr_write && csr_wdata[2]);
    assign tx_fifo_push  = csr_we && !lcr[7] && (csr_addr == CSR_THR) && (fcr[0] || tx_fifo_empty);
    assign tx_fifo_pop   = tx_start;
    assign tx_fifo_wdata = csr_wdata;

    assign tx_start      = tx_ready && !tx_fifo_empty;
    assign tx_data       = tx_fifo_rdata;

    sync_fifo #(
        .WIDTH (8),
        .DEPTH (16)
    ) tx_fifo (
        .clk   (clk),
        .rst   (tx_fifo_rst),
        .push  (tx_fifo_push),
        .pop   (tx_fifo_pop),
        .wdata (tx_fifo_wdata),
        .rdata (tx_fifo_rdata),
        .empty (tx_fifo_empty),
        .full  (tx_fifo_full),
        .count ()
    );

    uart_16550a_tx uart_tx (
        .clk              (clk),
        .rst              (rst),
        .baud_div         (baud_div),
        .tx_start         (tx_start),
        .tx_data          (tx_data),
        .tx_ready         (tx_ready),
        .tx               (tx),
        .lcr_word_len     (lcr[1:0]),
        .lcr_stop_bits    (lcr[2]),
        .lcr_parity_en    (lcr[3]),
        .lcr_parity_even  (lcr[4]),
        .lcr_parity_stick (lcr[5]),
        .lcr_break_en     (lcr[6]),
        .tsr_empty        (tsr_empty)
    );

    // === Register Assignment === //

    always_ff @(posedge clk) begin
        if (rst) begin
            dll <= 0;
            dlm <= 0;
            fcr <= 0;
            lcr <= 0;
            mcr <= 0;
            ier <= 0;
            scr <= 0;
        end
        else if (csr_we) begin
            unique0 case (csr_addr)
                CSR_LCR: lcr <= csr_wdata;
                CSR_MCR: mcr <= csr_wdata & 8'h3F;
                CSR_SCR: scr <= csr_wdata;

                CSR_THR: begin
                    if (lcr[7]) dll <= csr_wdata;
                    // THR writes are handled in tx_fifo_push
                end
                CSR_FCR: begin
                    if (csr_wdata[0]) fcr <= csr_wdata & 8'hC9; // RX/TX FIFO reset pins not registered; checked combinationally
                    else              fcr <= csr_wdata & 8'h01;
                end
                CSR_IER: begin
                    if (lcr[7]) dlm <= csr_wdata;
                    else        ier <= csr_wdata & 8'h0F;
                end
            endcase
        end
        else if (csr_re) begin
            unique case (csr_addr)
                CSR_IIR: csr_rdata <= iir;
                CSR_LCR: csr_rdata <= lcr;
                CSR_MCR: csr_rdata <= mcr;
                CSR_LSR: csr_rdata <= lsr;
                CSR_MSR: csr_rdata <= msr;
                CSR_SCR: csr_rdata <= scr;

                CSR_RBR: begin
                    if (lcr[7]) csr_rdata <= dll;
                    else        csr_rdata <= rx_fifo_rdata[7:0];
                end
                CSR_IER: begin
                    if (lcr[7]) csr_rdata <= dlm;
                    else        csr_rdata <= ier;
                end
            endcase
        end
    end

    // === LSR === //

    logic overrun_err;
    logic lsr_err_ack;

    always_ff @(posedge clk) begin
        if (rst) begin
            lsr_err_ack <= 0;
            overrun_err <= 0;
        end
        else begin
            if (rx_fifo_overrun_event) overrun_err <= 1;
            else if (lsr_read)         overrun_err <= 0;

            if (rx_fifo_head_update) lsr_err_ack <= 0;
            else if (lsr_read)       lsr_err_ack <= 1;
        end
    end

    assign lsr[0] = !rx_fifo_empty;
    assign lsr[1] = overrun_err;
    assign lsr[2] = !rx_fifo_empty && (rx_fifo_rdata[8]  && !lsr_err_ack);
    assign lsr[3] = !rx_fifo_empty && (rx_fifo_rdata[9]  && !lsr_err_ack);
    assign lsr[4] = !rx_fifo_empty && (rx_fifo_rdata[10] && !lsr_err_ack);
    assign lsr[5] = tx_fifo_empty;
    assign lsr[6] = tx_fifo_empty && tsr_empty;
    assign lsr[7] = fcr[0] && rx_fifo_pending_err;

    // === IIR === //

    logic rls;
    logic rda;
    logic cti;
    logic thre;
    logic ms;

    // IIR: THRE INTERRUPT //

    logic thre_active;
    logic thre_ack;

    assign thre_active = (iir[3:0] == 4'b0010);

    always_ff @(posedge clk) begin
        if (rst) begin
            thre_ack <= 0;
        end
        else begin
            if (tx_fifo_push && !tx_fifo_full) thre_ack <= 0;
            else if (iir_read && thre_active)  thre_ack <= 1;
        end
    end

    // IIR: CTI INTERRUPT //

    logic [9:0]  start_ticks; // Max ticks = (1 start, 8 data, 1 parity, 2 stop) * 16 * 4 = 10 bits
    logic [9:0]  data_ticks;
    logic [9:0]  parity_ticks;
    logic [9:0]  stop_ticks;
    logic [9:0]  timeout_ticks;

    logic [9:0]  timeout_counter;
    logic        timeout;

    logic [15:0] cti_baud_div_q; // To handle DLM/DLL writes
    logic [15:0] cti_baud_counter;
    logic        cti_baud_rst;
    logic        cti_tick_16x;

    assign start_ticks   = 16;
    assign data_ticks    = (10'd5 + 10'(lcr[1:0])) * 16;
    assign parity_ticks  = lcr[3] ? 16 : 0;
    assign stop_ticks    = {5'b0, calc_stop_ticks(lcr[1:0], lcr[2])} * 16;
    assign timeout_ticks = (start_ticks + data_ticks + parity_ticks + stop_ticks) * 4;

    assign cti_baud_rst  = rx_fifo_successful_pop || (!timeout && rx_fifo_successful_push); // Matches reset for timeout_counter

    always_ff @(posedge clk) begin
        if (rst) begin
            cti_baud_div_q   <= 0;
            cti_baud_counter <= 0;
            cti_tick_16x     <= 0;
        end
        else if (cti_baud_rst || (cti_baud_div_q == 0)) begin
            cti_baud_div_q   <= baud_div;
            cti_baud_counter <= 0;
            cti_tick_16x     <= 0;
        end
        else if (cti_baud_counter == (cti_baud_div_q - 1)) begin
            cti_baud_counter <= 0;
            cti_tick_16x     <= 1;
        end
        else begin
            cti_baud_counter <= cti_baud_counter + 1;
            cti_tick_16x     <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst || rx_fifo_successful_pop) begin
            timeout_counter <= 0;
            timeout         <= 0;
        end
        else if (!timeout) begin // If a timeout is set, nothing should change
            if (rx_fifo_successful_push) begin
                timeout_counter <= 0;
            end
            else if (cti_tick_16x && !rx_fifo_empty) begin
                timeout_counter <= timeout_counter + 1;

                if (timeout_counter == (timeout_ticks - 1)) begin
                    timeout <= 1;
                end
            end
        end
    end

    // IIR: Main Assignment //

    assign rls  = ier[2] && |lsr[4:1];
    assign rda  = ier[0] && (fcr[0] ? rx_fifo_trigger_met : !rx_fifo_empty);
    assign cti  = ier[0] && timeout;
    assign thre = ier[1] && tx_fifo_empty && !thre_ack;
    assign ms   = ier[3]; // ??

    always_comb begin
        if (rls)       iir[3:0] = 4'b0110;
        else if (rda)  iir[3:0] = 4'b0100;
        else if (cti)  iir[3:0] = 4'b1100;
        else if (thre) iir[3:0] = 4'b0010;
        else if (ms)   iir[3:0] = 4'b0000;
        else           iir[3:0] = 4'b0001;
    end

    assign iir[7:4] = {fcr[0], fcr[0], 2'b00};

    always_ff @(posedge clk) begin
        if (rst) irq <= 0;
        else     irq <= ~iir[0];
    end
endmodule
