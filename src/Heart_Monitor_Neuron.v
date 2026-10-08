/*
 * Copyright (c) 2025 davidbroughsmyth
 * SPDX-License-Identifier: Apache-2.0
 *
 * Heart_Monitor_Neuron.v - LIF with dynamic leak and window clear
 *
 * El proyecto original solo clasificaba los latidos, pero no utilizaba memoria ni reconocía patrones de latidos por lo que decidí añadirle una aplicación con prevención medica.
 * Optimizacion de area (2026): BIT_WIDTH reducido de 16 a 8.
 * Los pesos y el umbral estan pre-escalados por 1/16, manteniendo
 * el comportamiento funcional identico.
 */

`default_nettype none

module Heart_Monitor_Neuron #(
    parameter BIT_WIDTH = 8,
    parameter THRESHOLD = 8'h80      // 128 (antes 0x0800/16)
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   clear,
    input  wire                   tick_en,
    input  wire                   spike_up,
    input  wire                   spike_down,
    input  wire [BIT_WIDTH-1:0]   w_excitatory,
    input  wire [BIT_WIDTH-1:0]   w_inhibitory,
    input  wire [BIT_WIDTH-1:0]   leak_in,
    output reg                    anomaly_alert,
    output reg  [BIT_WIDTH-1:0]   v_mem
);

    reg [BIT_WIDTH-1:0] next_v_mem;

    always @(*) begin
        if (v_mem > leak_in) next_v_mem = v_mem - leak_in;
        else                 next_v_mem = {BIT_WIDTH{1'b0}};

        if (spike_up) begin
            next_v_mem = next_v_mem + w_excitatory;
        end
        if (spike_down) begin
            if (next_v_mem > w_inhibitory) next_v_mem = next_v_mem - w_inhibitory;
            else                           next_v_mem = {BIT_WIDTH{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (rst || clear) begin
            v_mem         <= {BIT_WIDTH{1'b0}};
            anomaly_alert <= 1'b0;
        end else if (tick_en) begin
            if (anomaly_alert) begin
                v_mem         <= {BIT_WIDTH{1'b0}};
                anomaly_alert <= 1'b0;
            end
            else if (next_v_mem >= THRESHOLD) begin
                v_mem         <= next_v_mem;
                anomaly_alert <= 1'b1;
            end
            else begin
                v_mem         <= next_v_mem;
                anomaly_alert <= 1'b0;
            end
        end else begin
            anomaly_alert <= 1'b0;
        end
    end
endmodule