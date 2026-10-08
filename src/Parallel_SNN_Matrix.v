/*
 * Copyright (c) 2025 davidbroughsmyth
 * SPDX-License-Identifier: Apache-2.0
 *
 * Parallel_SNN_Matrix.v - Class-specialized banded rate coding
 * Default NUM_NEURONS=5 (one neuron per AAMI class) for Tiny Tapeout area.
 *
 *El proyecto original solo clasificaba los latidos, pero no utilizaba memoria ni reconocia patrones de latidos por lo que decidi añadirle una aplicacion con prevencion medica.
 *
 * Optimizacion de area (2026): BIT_WIDTH reducido a 8, pesos escalados 1/16.
 */

`default_nettype none

module Parallel_SNN_Matrix #(
    parameter NUM_NEURONS = 5,
    parameter BIT_WIDTH   = 8,
    parameter THRESHOLD   = 8'h80,   // 128 (antes 0x0800/16)
    parameter LEAK        = 8'h00
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   clear,
    input  wire                   tick_en,

    input  wire                   spike_up_gentle,
    input  wire                   spike_down_gentle,
    input  wire                   spike_up_steep,
    input  wire                   spike_down_steep,
    input  wire                   spike_flip,

    output wire [NUM_NEURONS-1:0] out_spikes,
    output wire [(NUM_NEURONS*BIT_WIDTH)-1:0] matrix_v_mem
);

    wire steep_up_cont   = spike_up_steep   & ~spike_flip;
    wire steep_down_cont = spike_down_steep & ~spike_flip;

    wire [BIT_WIDTH-1:0] weights_exc [0:NUM_NEURONS-1];
    wire [BIT_WIDTH-1:0] weights_inh [0:NUM_NEURONS-1];
    wire [BIT_WIDTH-1:0] leak_val    [0:NUM_NEURONS-1];
    wire [NUM_NEURONS-1:0] map_spike_up;
    wire [NUM_NEURONS-1:0] map_spike_down;

    genvar i;
    generate
        for (i = 0; i < NUM_NEURONS; i = i + 1) begin : config_loop

            // Pesos escalados por 1/16 respecto al diseno original
            case (i % 5)
                0: begin
                    assign map_spike_up[i]   = spike_up_gentle;
                    assign map_spike_down[i] = spike_down_gentle | spike_up_steep | spike_down_steep | spike_flip;
                    assign weights_exc[i]    = 8'h30;   // 0x0300 / 16
                    assign weights_inh[i]    = 8'h40;   // 0x0400 / 16
                    assign leak_val[i]       = 8'h01;   // 0x0010 / 16
                end
                1: begin
                    assign map_spike_up[i]   = spike_down_gentle;
                    assign map_spike_down[i] = spike_up_gentle | spike_up_steep | spike_down_steep | spike_flip;
                    assign weights_exc[i]    = 8'h30;
                    assign weights_inh[i]    = 8'h40;
                    assign leak_val[i]       = 8'h01;
                end
                2: begin
                    assign map_spike_up[i]   = steep_up_cont;
                    assign map_spike_down[i] = steep_down_cont | spike_up_gentle | spike_down_gentle | spike_flip;
                    assign weights_exc[i]    = 8'h60;   // 0x0600 / 16
                    assign weights_inh[i]    = 8'h40;
                    assign leak_val[i]       = 8'h08;   // 0x0080 / 16
                end
                3: begin
                    assign map_spike_up[i]   = steep_down_cont;
                    assign map_spike_down[i] = steep_up_cont | spike_up_gentle | spike_down_gentle | spike_flip;
                    assign weights_exc[i]    = 8'h60;
                    assign weights_inh[i]    = 8'h40;
                    assign leak_val[i]       = 8'h08;
                end
                4: begin
                    assign map_spike_up[i]   = spike_flip;
                    assign map_spike_down[i] = (spike_up_gentle | spike_down_gentle |
                                               steep_up_cont | steep_down_cont) & ~spike_flip;
                    assign weights_exc[i]    = 8'h50;   // 0x0500 / 16
                    assign weights_inh[i]    = 8'h20;   // 0x0200 / 16
                    assign leak_val[i]       = 8'h04;   // 0x0040 / 16
                end
            endcase

            Heart_Monitor_Neuron #(
                .BIT_WIDTH(BIT_WIDTH), .THRESHOLD(THRESHOLD)
            ) neuron_inst (
                .clk(clk), .rst(rst), .clear(clear), .tick_en(tick_en),
                .spike_up(map_spike_up[i]),
                .spike_down(map_spike_down[i]),
                .w_excitatory(weights_exc[i]),
                .w_inhibitory(weights_inh[i]),
                .leak_in(leak_val[i]),
                .anomaly_alert(out_spikes[i]),
                .v_mem(matrix_v_mem[(i*BIT_WIDTH) +: BIT_WIDTH])
            );
        end
    endgenerate
endmodule