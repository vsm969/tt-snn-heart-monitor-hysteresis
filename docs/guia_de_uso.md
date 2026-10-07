# User Guide — How to operate the chip

This guide explains how to interact with the SNN Arrhythmia Detector once it is fabricated and mounted on a Tiny Tapeout demo board.

## Table of contents

1. [Pin summary](#pin-summary)
2. [Inference mode](#inference-mode)
3. [Calibration mode](#calibration-mode)
4. [Test mode](#test-mode)
5. [Interpreting the outputs](#interpreting-the-outputs)

## Pin summary

See the [README](../README.md#-pinout) for the full pinout table.

Key pins:

| Pin | Name | Purpose |
|---|---|---|
| `ui_in[7:0]` | `ADC_data[7:0]` | Lower 8 bits of the ECG sample |
| `uio_in[3:0]` | `ADC_data[11:8]` | Upper 4 bits of the ECG sample |
| `uio_in[4]` | `sample_en` | Pulse high to submit a sample |
| `uio_in[5]` | `mode_sel` | Calibration mode selector |
| `uio_in[6]` | `force_class` | Test mode selector |
| `uo_out[0]` | `alarm` | Arrhythmia alarm |
| `uo_out[1]` | `pattern_detected` | Pattern pulse |
| `uo_out[4:2]` | `class_out` | Beat classification |

## Inference mode

This is the normal operating mode.

1. Set `mode_sel = 0` and `force_class = 0`.
2. For each new ADC sample:
   - Place the 12-bit sample on `{uio_in[3:0], ui_in[7:0]}`.
   - Pulse `sample_en` high for one clock cycle.
3. After the SNN finishes processing the window, `diagnostic_valid` goes high and `class_out` holds the classification.
4. If 3 consecutive anomalies occur, `alarm` goes high and stays high until a Normal beat is seen.

## Calibration mode

Calibration adapts the internal threshold of the segmenter to the patient's baseline.

1. Set `mode_sel = 1`.
2. Send Normal beats (classes 0) as they occur naturally.
3. Each Normal sample reduces the internal threshold by `THRESHOLD_STEP`.
4. After `CALIB_MAX` samples, the threshold stops changing.
5. Set `mode_sel = 0` to return to inference mode.

The calibrated threshold is used for R-peak detection in subsequent inference runs.

## Test mode

Test mode bypasses the SNN and injects a class directly.

1. Set `force_class = 1`.
2. Place a 3-bit class value on `ui_in[2:0]`.
3. Pulse `sample_en` high for one cycle.
4. The Decision Engine processes the forced class as if it came from the SNN.

This is useful for:

- Verifying the hysteresis logic in isolation.
- Debugging the Decision Engine without an ECG signal.
- Automated testing in a production environment.

## Interpreting the outputs

| Output | Meaning |
|---|---|
| `alarm = 1` | At least 3 consecutive anomalous beats have been detected |
| `pattern_detected = 1` | A pattern was just detected (one-cycle pulse) |
| `class_out` | Classification of the most recent beat |
| `diagnostic_valid = 1` | The classification is stable and valid |
| `alarm_strobe = 1` | Short pulse from the original core (debug) |

### Class values

| Value | Class | Anomalous? |
|---|---|---|
| 0 | Normal | No |
| 1 | Supraventricular | Yes |
| 2 | Ventricular | Yes |
| 3 | Fusion | No |
| 4 | Unknown | Yes |

## Example: detecting a Ventricular run

Suppose the SNN outputs this sequence:

Normal -> Ventricular -> Ventricular -> Ventricular -> Normal


Expected behavior:

| After beat # | Class | alarm | pattern_detected |
|---|---|---|---|
| 1 (Normal) | 0 | 0 | 0 |
| 2 (Ventricular) | 2 | 0 | 0 |
| 3 (Ventricular) | 2 | 0 | 0 |
| 4 (Ventricular) | 2 | 1 | 1 |
| 5 (Normal) | 0 | 0 | 0 |

The alarm activates at beat #4 (the 3rd Ventricular) and clears at beat #5 (the Normal beat).
