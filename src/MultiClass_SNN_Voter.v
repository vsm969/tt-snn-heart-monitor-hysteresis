/*
 * Copyright (c) 2025 davidbroughsmyth
 * SPDX-License-Identifier: Apache-2.0
 *
 * MultiClass_SNN_Voter.v - Majority vote with required win margin
 *
 * Optimizacion de area (2026):
 *   - Contadores reducidos de 16 a 8 bits.
 *   - Eliminado step_sum: ahora usa input_spikes directamente.
 *   - max_count, second_count, c reducidos de 16 a 8 bits.
 */

`default_nettype none

module MultiClass_SNN_Voter #(
    parameter PARALLEL_NEURONS = 5,
    parameter BIT_WIDTH        = 8,
    parameter WIN_MARGIN       = 8'd8
)(
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         window_start,
    input  wire                         window_end,
    input  wire [PARALLEL_NEURONS-1:0]  input_spikes,

    output reg  [2:0]                   assigned_class,
    output reg                          valid_out
);

    reg [BIT_WIDTH-1:0] count_N, count_S, count_V, count_F, count_Q;

    reg [BIT_WIDTH-1:0] max_count;
    reg [BIT_WIDTH-1:0] second_count;
    reg [2:0]           best_class;
    reg [BIT_WIDTH-1:0] c;

    always @(posedge clk) begin
        if (rst) begin
            count_N <= 0; count_S <= 0; count_V <= 0; count_F <= 0; count_Q <= 0;
            assigned_class <= 3'b111; valid_out <= 0;
        end else if (window_start) begin
            count_N <= 0; count_S <= 0; count_V <= 0; count_F <= 0; count_Q <= 0;
            valid_out <= 0;
        end else if (window_end) begin
            valid_out <= 1;

            max_count    = count_N;
            best_class   = 3'd0;
            second_count = 0;

            c = count_S;
            if (c > max_count) begin second_count = max_count; max_count = c; best_class = 3'd1; end
            else if (c > second_count) second_count = c;

            c = count_V;
            if (c > max_count) begin second_count = max_count; max_count = c; best_class = 3'd2; end
            else if (c > second_count) second_count = c;

            c = count_F;
            if (c > max_count) begin second_count = max_count; max_count = c; best_class = 3'd3; end
            else if (c > second_count) second_count = c;

            c = count_Q;
            if (c > max_count) begin second_count = max_count; max_count = c; best_class = 3'd4; end
            else if (c > second_count) second_count = c;

            if ((max_count < second_count + WIN_MARGIN) && (best_class != 3'd4))
                assigned_class <= 3'd4;
            else
                assigned_class <= best_class;
        end else begin
            // Uso directo de input_spikes (cada uno es 1 bit)
            count_N <= count_N + {7'b0, input_spikes[0]};
            count_S <= count_S + {7'b0, input_spikes[1]};
            count_V <= count_V + {7'b0, input_spikes[2]};
            count_F <= count_F + {7'b0, input_spikes[3]};
            count_Q <= count_Q + {7'b0, input_spikes[4]};
            valid_out <= 0;
        end
    end
endmodule