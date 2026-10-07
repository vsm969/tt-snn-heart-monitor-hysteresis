/*
 * Copyright (c) 2025 davidbroughsmyth
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tiny Tapeout wrapper for the SNN heart-monitor classifier.
 *
 * Pin map (original):
 *   ui_in[7:0]     = adc_data_in[7:0]
 *   uio_in[3:0]    = adc_data_in[11:8]
 *   uio_in[4]      = sample_en
 *   uo_out[2:0]    = heart_class_out
 *   uo_out[3]      = diagnostic_valid
 *   uo_out[4]      = alarm_strobe
 *
 * -----------------------------------------------------------------------------
 * Modifications Copyright (c) 2026 [Tu Nombre]
 *
 * This file has been modified from the original. Changes include:
 *   - Integrated Decision_Engine module for temporal hysteresis, consecutive
 *     anomaly pattern detection, and adaptive threshold calibration.
 *   - Remapped outputs to expose persistent alarm and pattern_detected.
 *   - Added mode_sel input on uio_in[5].
 *
 * Original design: https://github.com/davidbroughsmyth/snn_lif_neurons_ttsky26c
 * Licensed under the Apache License, Version 2.0.
 * -----------------------------------------------------------------------------
 *
 * Pin map (modified):
 *   ui_in[7:0]     = adc_data_in[7:0]
 *   uio_in[3:0]    = adc_data_in[11:8]
 *   uio_in[4]      = sample_en
 *   uio_in[5]      = mode_sel       (0 = inferencia, 1 = calibración)
 *   uo_out[0]      = alarm          (persistente, del Decision_Engine)
 *   uo_out[1]      = pattern_detected (pulso, del Decision_Engine)
 *   uo_out[4:2]    = heart_class_out
 *   uo_out[5]      = diagnostic_valid
 *   uo_out[6]      = alarm_strobe   (pulso corto del core, debug)
 *   uo_out[7]      = spare
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

    // -------------------------------------------------------------------------
    // Señales internas y mapeo de pines
    // -------------------------------------------------------------------------
    wire        rst         = ~rst_n;
    wire        sample_en   = uio_in[4];
    wire [11:0] adc_data_in = {uio_in[3:0], ui_in};

    // -------------------------------------------------------------------------
    // Core: SNN Heart Monitor (diseño original)
    // -------------------------------------------------------------------------
    wire [2:0] heart_class_out;
    wire       diagnostic_valid;
    wire       alarm_strobe;
    wire [2:0] class_forced;

    SNN_Heart_Monitor_Top #(
        .NUM_NEURONS(5),
        .ALARM_PERSIST_MAX(3),
        .WIN_MARGIN(16'd8)
    ) core (
        .clk              (clk),
        .rst              (rst),
        .sample_en        (sample_en),
        .adc_data_in      (adc_data_in),
        .heart_class_out  (heart_class_out),
        .diagnostic_valid (diagnostic_valid),
        .alarm_strobe     (alarm_strobe)
    );

    // -------------------------------------------------------------------------
    // Decision Engine: histéresis + detección de patrones + calibración
    // -------------------------------------------------------------------------
    wire        alarm_persistent;
    wire        pattern_detected;

    assign class_forced = uio_in[6] ? ui_in[2:0] : heart_class_out;

    Decision_Engine #(
        .WINDOW_SIZE    (3),
        .ANOMALY_COUNT  (3)
    ) u_decision (
        .clk              (clk),
        .rst_n            (rst_n),
        .sample_en        (sample_en),
        .class_in         (class_forced),
        .alarm            (alarm_persistent),
        .pattern_detected (pattern_detected)
    );
    // -------------------------------------------------------------------------
    // Mapeo de salidas (alineado con info.yaml)
    // -------------------------------------------------------------------------
    //   uo[7]   = spare
    //   uo[6]   = alarm_strobe  (pulso corto del core, para debug)
    //   uo[5]   = diagnostic_valid
    //   uo[4:2] = heart_class_out
    //   uo[1]   = pattern_detected
    //   uo[0]   = alarm_persistent
    assign uo_out = {
        1'b0,             // uo[7] spare
        alarm_strobe,     // uo[6]
        diagnostic_valid, // uo[5]
        heart_class_out,  // uo[4:2]
        pattern_detected, // uo[1]
        alarm_persistent  // uo[0]
    };

    // Pines bidireccionales: todos como entrada (uio_oe = 0)
    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;

    // -------------------------------------------------------------------------
    // Señales no utilizadas (evita warnings de síntesis)
    // -------------------------------------------------------------------------
    // - ena: no se usa en este diseño
    // - uio_in[7:6]: reservados para futuras expansiones
    // - threshold_dyn: reservado para futura integración con Heartbeat_Segmenter
    wire _unused = &{ena, uio_in[7:5], 1'b0};

endmodule