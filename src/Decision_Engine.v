// -----------------------------------------------------------------------------
// Decision_Engine.v
//
// Motor de decisión con histéresis temporal.
// Parte del proyecto SNN Heart Monitor (basado en snn_lif_neurons_ttsky26c
// de David Broughsmyth, Apache 2.0).
//
// Modificaciones Copyright (c) 2026 Vicente Antonio San Martín Fuentes
// Cambios respecto al original:
//   - Añadido registro de historial de clasificaciones.
//   - Detector de N anomalías consecutivas con ventana deslizante.
//   - Alarma persistente con histéresis (se limpia con un latido Normal).
//
// Nota: el modo de calibración adaptativa fue eliminado en una iteración
// de optimización de área para ajustar el diseño a un tile 1x1.
// -----------------------------------------------------------------------------

module Decision_Engine #(
    parameter integer WINDOW_SIZE   = 3,
    parameter integer ANOMALY_COUNT = 3
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_en,
    input  wire [2:0]  class_in,
    output reg         alarm,
    output reg         pattern_detected
);

    // -------------------------------------------------------------------------
    // 1. Registro de historial
    // -------------------------------------------------------------------------
    reg [2:0] history [0:WINDOW_SIZE-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < WINDOW_SIZE; i = i + 1)
                history[i] <= 3'd0;
        end
        else if (sample_en) begin
            for (i = WINDOW_SIZE-1; i > 0; i = i - 1)
                history[i] <= history[i-1];
            history[0] <= class_in;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Detección de anomalías (usa la clase entrante + historial)
    // -------------------------------------------------------------------------
    function automatic is_anomaly(input [2:0] c);
        is_anomaly = (c == 3'd1) || (c == 3'd2) || (c == 3'd4);
    endfunction

    reg window_would_be_full;
    integer j;

    always @(*) begin
        window_would_be_full = is_anomaly(class_in);
        for (j = 0; j < ANOMALY_COUNT - 1; j = j + 1) begin
            if (!is_anomaly(history[j]))
                window_would_be_full = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Máquina de estados de la alarma (histéresis)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alarm            <= 1'b0;
            pattern_detected <= 1'b0;
        end
        else if (sample_en) begin
            if (window_would_be_full) begin
                alarm            <= 1'b1;
                pattern_detected <= 1'b1;
            end
            else begin
                pattern_detected <= 1'b0;

                // Limpiar la alarma si llega un latido Normal
                if (class_in == 3'd0)
                    alarm <= 1'b0;
            end
        end
        else begin
            pattern_detected <= 1'b0;
        end
    end

endmodule