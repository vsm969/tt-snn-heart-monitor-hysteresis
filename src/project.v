/*
 * Copyright (c) 2025 davidbroughsmyth
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper for the SNN heart-monitor classifier.
 *
 * -----------------------------------------------------------------------------
 * Modifications Copyright (c) 2026 Vicente Antonio San Martin Fuentes
 *
* El proyecto original solo clasificaba los latidos, pero no utilizaba memoria ni reconocia patrones de latidos por lo que decidi añadirle una aplicacion con prevencion medica.
 *
 * This file has been modified from the original. Changes include:
 *   - Integrated Decision_Engine module for temporal hysteresis, consecutive
 *     anomaly pattern detection, and adaptive threshold calibration.
 *   - Remapped outputs to expose persistent alarm and pattern_detected.
 *   - Added mode_sel input on uio_in[5].
 *   - Functional calibration: threshold_dyn routed to SNN core.
 *
 * Original design: https://github.com/davidbroughsmyth/snn_lif_neurons_ttsky26c
 * Licensed under the Apache License, Version 2.0.
 * -----------------------------------------------------------------------------
 */

`default_nettype none

module tt_um_arrhythmia_detector (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire        rst         = ~rst_n;
    wire        sample_en   = uio_in[4];
    wire        mode_sel    = uio_in[5];
    wire [11:0] adc_data_in = {uio_in[3:0], ui_in};

    wire [2:0] heart_class_out;
    wire       diagnostic_valid;
    wire       alarm_strobe;
    wire [2:0] class_forced;

    // -------------------------------------------------------------------------
    // Decision Engine (declarado antes del core para poder conectar threshold)
    // -------------------------------------------------------------------------
    wire        alarm_persistent;
    wire        pattern_detected;
    wire [11:0] threshold_dyn;

    assign class_forced = uio_in[6] ? ui_in[2:0] : heart_class_out;

    Decision_Engine #(
        .WINDOW_SIZE    (3),
        .ANOMALY_COUNT  (3),
        .THRESHOLD_INIT (12'd2200),
        .THRESHOLD_STEP (12'd50),
        .CALIB_MAX      (4'd8)
    ) u_decision (
        .clk              (clk),
        .rst_n            (rst_n),
        .sample_en        (sample_en),
        .class_in         (class_forced),
        .mode_sel         (mode_sel),
        .alarm            (alarm_persistent),
        .pattern_detected (pattern_detected),
        .threshold_out    (threshold_dyn)
    );

    // -------------------------------------------------------------------------
    // SNN core (con threshold dinamico)
    // -------------------------------------------------------------------------
    SNN_Heart_Monitor_Top #(
        .NUM_NEURONS(5),
        .ALARM_PERSIST_MAX(3),
        .WIN_MARGIN(8'd8)
    ) core (
        .clk              (clk),
        .rst              (rst),
        .sample_en        (sample_en),
        .adc_data_in      (adc_data_in),
        .threshold_in     (threshold_dyn),
        .heart_class_out  (heart_class_out),
        .diagnostic_valid (diagnostic_valid),
        .alarm_strobe     (alarm_strobe)
    );

    // -------------------------------------------------------------------------
    // Mapeo de salidas
    // -------------------------------------------------------------------------
    assign uo_out = {
        1'b0,             // uo[7] spare
        alarm_strobe,     // uo[6]
        diagnostic_valid, // uo[5]
        heart_class_out,  // uo[4:2]
        pattern_detected, // uo[1]
        alarm_persistent  // uo[0]
    };

    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    wire _unused = &{ena, uio_in[7], 1'b0};

endmodule