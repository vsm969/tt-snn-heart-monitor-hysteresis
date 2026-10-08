// -----------------------------------------------------------------------------
// Decision_Engine.v
//
// Motor de decisión con histéresis temporal y calibración adaptativa.
// Parte del proyecto SNN Heart Monitor (basado en snn_lif_neurons_ttsky26c
// de David Broughsmyth, Apache 2.0).
//
//El proyecto original solo clasificaba los latidos, pero no utilizaba memoria ni reconocía patrones de latidos por lo que decidí añadirle una aplicación con prevención medica.
//
// Modificaciones Copyright (c) 2026 Vicente Antonio San Martín Fuentes
// Cambios respecto al original:
//   - Historial de anomalías consecutivas mediante contador (área optimizada).
//   - Detección de N anomalías consecutivas.
//   - Alarma persistente con histéresis (se limpia con un latido Normal).
//   - Calibración adaptativa del umbral de detección de pico R, conectada
//     de forma funcional al Heartbeat_Segmenter.
// -----------------------------------------------------------------------------

module Decision_Engine #(
    parameter [11:0]  THRESHOLD_INIT = 12'd2200,
    parameter [11:0]  THRESHOLD_STEP = 12'd50,
    parameter [3:0]   CALIB_MAX      = 4'd8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,
    input  wire [2:0]  class_in,
    input  wire        mode_sel,
    output reg         alarm,
    output reg         pattern_detected,
    output reg  [11:0] threshold_out
);

    // -------------------------------------------------------------------------
    // 1. Detección de anomalía (una sola expresión booleana)
    //    Clases anómalas: 1 (001), 2 (010), 4 (100)
    //    is_anomaly = c[2] | (c[1] ^ c[0])
    // -------------------------------------------------------------------------
    wire is_anomaly = class_in[2] | (class_in[1] ^ class_in[0]);

    // -------------------------------------------------------------------------
    // 2. Contador de anomalías consecutivas (reemplaza el shift register)
    //    El contador satura en ANOMALY_COUNT.
    // -------------------------------------------------------------------------
    reg [1:0] anomaly_count;

    // -------------------------------------------------------------------------
    // 3. Máquina de estados de la alarma (histéresis) + calibración
    // -------------------------------------------------------------------------
    reg [3:0] calib_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            anomaly_count     <= 2'd0;
            alarm             <= 1'b0;
            pattern_detected  <= 1'b0;
            threshold_out     <= THRESHOLD_INIT;
            calib_count       <= 4'd0;
        end
        else begin
            // Default: limpiar el pulso cada ciclo (fuera de los if)
            pattern_detected <= 1'b0;

            if (mode_sel && sample_en) begin
                // Modo calibración
                if (class_in == 3'd0 && calib_count < CALIB_MAX) begin
                    threshold_out <= threshold_out - THRESHOLD_STEP;
                    calib_count   <= calib_count + 1'b1;
                end
            end
            else if (sample_en) begin
                if (is_anomaly) begin
                    if (anomaly_count < 2'd3)
                        anomaly_count <= anomaly_count + 1'b1;
                    if (anomaly_count == 2'd2) begin
                        pattern_detected <= 1'b1;
                        alarm            <= 1'b1;
                    end
                end
                else begin
                    anomaly_count <= 2'd0;
                    if (class_in == 3'd0)
                        alarm <= 1'b0;
                end
            end
        end
    end
endmodule