// -----------------------------------------------------------------------------
// Decision_Engine.v
//
// Motor de decisión con histéresis temporal y calibración adaptativa.
// Parte del proyecto SNN Heart Monitor (basado en snn_lif_neurons_ttsky26c
// de David Broughsmyth, Apache 2.0).
//
// Modificaciones Copyright (c) 2026 [Tu Nombre]
// Cambios respecto al original:
//   - Añadido registro de historial de clasificaciones.
//   - Detector de N anomalías consecutivas con ventana deslizante.
//   - Modo de calibración que ajusta el umbral del segmentador.
// -----------------------------------------------------------------------------

module Decision_Engine #(
    parameter integer WINDOW_SIZE   = 5,
    parameter integer ANOMALY_COUNT = 3,
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
    // 1. Registro de historial
    // -------------------------------------------------------------------------
    reg [2:0] history [0:WINDOW_SIZE-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < WINDOW_SIZE; i = i + 1)
                history[i] <= 3'd0;
        end
        else if (sample_en && !mode_sel) begin
            for (i = WINDOW_SIZE-1; i > 0; i = i - 1)
                history[i] <= history[i-1];
            history[0] <= class_in;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Detección de anomalías (usando la clase entrante + historial)
    // -------------------------------------------------------------------------
    // Nota: evaluamos el "futuro" historial: {class_in, history[0], history[1]}
    // Esto corrige el bug de sincronización de la versión anterior.

    function automatic is_anomaly(input [2:0] c);
        is_anomaly = (c == 3'd1) || (c == 3'd2) || (c == 3'd4);
    endfunction

    // Ventana proyectada: la nueva clase + las ANOMALY_COUNT-1 más recientes
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
        else if (sample_en && !mode_sel) begin
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

    // -------------------------------------------------------------------------
    // 4. Modo calibración
    // -------------------------------------------------------------------------
    reg [3:0] calib_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold_out <= THRESHOLD_INIT;
            calib_count   <= 4'd0;
        end
        else if (mode_sel && sample_en) begin
            if (class_in == 3'd0 && calib_count < CALIB_MAX) begin
                threshold_out <= threshold_out - THRESHOLD_STEP;
                calib_count   <= calib_count + 1'b1;
            end
        end
    end

endmodule
