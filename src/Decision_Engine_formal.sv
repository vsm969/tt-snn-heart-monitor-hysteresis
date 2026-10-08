// -----------------------------------------------------------------------------
// Decision_Engine_formal.sv
//
// Formal verification wrapper for the Decision_Engine module.
// Only used when running SymbiYosys.
// -----------------------------------------------------------------------------

`default_nettype none

module Decision_Engine_formal (
    input wire clk
);

    // -------------------------------------------------------------------------
    // Reset generation: rst_n is 0 for the first 2 cycles, then 1
    // -------------------------------------------------------------------------
    reg rst_n = 0;
    reg [1:0] rst_cnt = 0;

    always @(posedge clk) begin
        if (rst_cnt < 2) begin
            rst_cnt <= rst_cnt + 1;
        end
        else begin
            rst_n <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Free inputs (driven by the solver)
    // -------------------------------------------------------------------------
    reg       sample_en;
    reg [2:0] class_in;
    reg       mode_sel;

    wire        alarm;
    wire        pattern_detected;
    wire [11:0] threshold_out;

    // -------------------------------------------------------------------------
    // DUT instance
    // -------------------------------------------------------------------------
    Decision_Engine #(
        .WINDOW_SIZE    (3),
        .ANOMALY_COUNT  (3),
        .THRESHOLD_INIT (12'd2200),
        .THRESHOLD_STEP (12'd50),
        .CALIB_MAX      (4'd8)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .sample_en        (sample_en),
        .class_in         (class_in),
        .mode_sel         (mode_sel),
        .alarm            (alarm),
        .pattern_detected (pattern_detected),
        .threshold_out    (threshold_out)
    );

    // -------------------------------------------------------------------------
    // Assumption: class_in is always a valid class (0..4)
    // -------------------------------------------------------------------------
    always @(*) assume (class_in <= 3'd4);

    // -------------------------------------------------------------------------
    // Property 1: pattern_detected is a pulse (never two cycles in a row)
    // -------------------------------------------------------------------------
    reg prev_pattern = 0;
    always @(posedge clk) begin
        if (rst_n && prev_pattern && pattern_detected) begin
            assert (0);
        end
        prev_pattern <= pattern_detected;
    end

    // -------------------------------------------------------------------------
    // Property 2: alarm is only cleared by class 0 (Normal)
    // -------------------------------------------------------------------------
    reg       a_alarm_prev  = 0;
    reg       a_sample_prev = 0;
    reg       a_mode_prev   = 0;
    reg [2:0] a_class_prev  = 0;

    always @(posedge clk) begin
        if (rst_n && a_sample_prev && !a_mode_prev
            && a_alarm_prev && !alarm) begin
            assert (a_class_prev == 3'd0);
        end
        a_alarm_prev  <= alarm;
        a_sample_prev <= sample_en;
        a_mode_prev   <= mode_sel;
        a_class_prev  <= class_in;
    end

    // -------------------------------------------------------------------------
    // Property 3: while reset is active, alarm and pattern are 0
    // -------------------------------------------------------------------------
    always @(*) begin
        if (!rst_n) begin
            assert (alarm            == 0);
            assert (pattern_detected == 0);
        end
    end

endmodule

`default_nettype wire