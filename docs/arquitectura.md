# Architecture — Extended Documentation

This document provides a deeper look at the internal architecture of the
SNN Arrhythmia Detector with Hysteresis.

## Table of contents

1. [System overview](#system-overview)
2. [SNN core](#snn-core)
3. [Decision Engine](#decision-engine)
4. [Signal flow example](#signal-flow-example)
5. [Timing considerations](#timing-considerations)

## System overview

The design is organized in two functional blocks:

- **SNN Core** (original): classifies a single heartbeat.
- **Decision Engine** (new): remembers recent classifications and decides when to raise an alarm.

Both blocks share the same clock (`clk`) and reset (`rst_n`).

## SNN core

The SNN core processes a 12-bit ADC sample per clock cycle when `sample_en` is high.

### Heartbeat Segmenter

A three-state FSM that detects the R-peak of the ECG waveform:

| State | Behavior |
|---|---|
| `SEARCH` | Waits until the sample exceeds `threshold_in` |
| `EVALUATE` | Collects samples for `EVAL_CYCLES` (configurable) |
| `REFRACTORY` | Waits for `REFRACTORY_CYCLES` to avoid double-detection |

The output signals are `window_start` (one pulse when a beat is detected) and `window_end` (one pulse when the evaluation window ends).

### Delta Encoder

Converts the raw ADC samples into a stream of spikes:

| Spike | Meaning |
|---|---|
| `spike_up` | The waveform is rising |
| `spike_down` | The waveform is falling |
| `spike_up_gentle` | Gentle rise |
| `spike_down_gentle` | Gentle fall |
| `spike_up_steep` | Steep rise |
| `spike_down_steep` | Steep fall |
| `spike_flip` | Direction change |

Thresholds (`DELTA_THRESHOLD`, `STEEP_THRESHOLD`) are configurable.

### Parallel SNN Matrix

An array of 5 Leaky Integrate-and-Fire (LIF) neurons, one per class. Each neuron accumulates excitatory and inhibitory contributions based on the spikes it receives. When the membrane potential `v_mem` exceeds the `THRESHOLD`, the neuron fires (`anomaly_alert`).

The weights are class-specific. For example:

| Class | Excitatory weights | Inhibitory weights | Leak |
|---|---|---|---|
| 0 (Normal) | 8'h30 | 8'h40 | 8'h01 |
| 2 (Ventricular) | 8'h60 | 8'h40 | 8'h08 |
| 4 (Unknown) | 8'h50 | 8'h20 | 8'h04 |

### MultiClass Voter

Counts how many times each neuron fired during the current window. When `window_end` pulses, it selects the class with the most votes. If the winning class does not have a minimum margin over the runner-up, it reports class 4 (Unknown).

## Decision Engine

The Decision Engine is a small module that adds temporal reasoning.

### Inputs

- `clk`, `rst_n`: clock and reset.
- `sample_en`: high when a new classification is ready.
- `class_in`: the current class (from the voter or forced via test mode).
- `mode_sel`: 0 = inference, 1 = calibration.

### Outputs

- `alarm`: persistent alarm.
- `pattern_detected`: pulse when a pattern is detected.
- `threshold_out`: dynamically adjusted threshold for the segmenter.

### Internal logic

1. **Anomaly detection** — a combinational expression:

   ```verilog
   wire is_anomaly = class_in[2] | (class_in[1] ^ class_in[0]);

2. **Anomaly counter** — a 2-bit register that increments on each anomaly and resets on a Normal beat:

   ```verilog
    if (is_anomaly)
        if (anomaly_count < 2'd3) anomaly_count <= anomaly_count + 1'b1;
    else
        anomaly_count <= 2'd0;

3. **Pattern detection** — when the counter reaches 2 (meaning this is the 3rd consecutive anomaly), a pulse is generated:

   ```verilog
    if (anomaly_count == 2'd2) begin
        pattern_detected <= 1'b1;
        alarm            <= 1'b1;
    end

4. **Hysteresis** — the alarm is only cleared when a Normal beat arrives:

   ```verilog
    if (class_in == 3'd0)
        alarm <= 1'b0;

5. **Calibration** — when mode_sel is high and the class is Normal, the threshold is reduced:

   ```verilog
    if (mode_sel && sample_en && class_in == 3'd0 && calib_count < CALIB_MAX)
        threshold_out <= threshold_out - THRESHOLD_STEP;


## Signal flow example

Consider a sequence of 3 Ventricular beats followed by 1 Normal beat.

| Cycle | sample_en | class_in | anomaly_count | alarm | pattern_detected |
|---|---|---|---|---|---|
| 0 | 0 | X | 0 | 0 | 0 |
| 1 | 1 | 2 (Ventricular) | 1 | 0 | 0 |
| 2 | 1 | 2 | 2 | 0 | 0 |
| 3 | 1 | 2 | 3 | 1 | 1 |
| 4 | 1 | 0 (Normal) | 0 | 0 | 0 |

## Timing considerations

The Decision Engine runs at the same clock frequency as the SNN core. The 2-bit counter and the FSM are synchronous; all updates happen on the rising edge of `clk`.

The critical path of the module is the chain:


class_in → is_anomaly → anomaly_count → window_would_be_full → alarm

This path is short, and the design closes timing at 40 MHz with margin in the SKY130A process.

## Formal verification

The `Decision_Engine` was formally verified using SymbiYosys and Z3.
The formal wrapper is in `src/Decision_Engine_formal.sv` and the
configuration in `src/decision_engine.sby`.

Three properties are proved for all input combinations within 25 cycles:

1. **Pulse width**: `pattern_detected` is never high two cycles in a row.
2. **Hysteresis**: the alarm is only cleared by a Normal beat (class 0).
3. **Reset**: while `rst_n` is low, both `alarm` and `pattern_detected`
   are 0.

The formal verification caught a real bug in the first version of the
module: `pattern_detected` could persist for more than one cycle when
`sample_en` was deasserted right after the third anomaly. The fix
consisted of moving the default assignment `pattern_detected <= 1'b0;`
outside the `if (sample_en)` branches, so the pulse auto-clears every
cycle.

After the fix, the formal proof completes with **PASS** in a few seconds.