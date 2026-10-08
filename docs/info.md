<!---
This file is used to generate your project datasheet.
Please fill in the information below and delete any unused sections.
You can include images in this folder and reference them in the markdown.
Each image must be less than 512 kB, combined total under 1 MB.
-->

## How it works

This chip implements a **cardiac arrhythmia detector** using a **Spiking Neural Network (SNN)** followed by a **Decision Engine** that adds temporal reasoning, being useful in the future to apply it in everyday medical aplication, improving people's lives.

The design is a derivative of the [`snn_lif_neurons_ttsky26c`](https://github.com/davidbroughsmyth/snn_lif_neurons_ttsky26c) project by David Broughsmyth, wich was a great start, but it could be improved, which classifies each heartbeat into one of five categories:

- `0` — Normal
- `1` — Supraventricular
- `2` — Ventricular
- `3` — Fusion
- `4` — Unknown

### SNN Core

The SNN core processes a 12-bit ADC sample per clock cycle when `sample_en` is high. It uses:

1. A **Heartbeat Segmenter** to detect the R-peak of each beat.
2. A **Delta Encoder** to compress the waveform into sparse events.
3. A **Parallel SNN Matrix** of 5 Leaky Integrate-and-Fire (LIF) neurons, one per class.
4. A **MultiClass Voter** that selects the winning class.

### Decision Engine (new)

The `Decision_Engine` module adds three features on top of the SNN:

1. **Anomaly counter**: tracks consecutive anomalous beats (classes 1, 2, or 4).
2. **Pattern detector**: when the counter reaches 3, the alarm is activated. This evaluation includes the incoming class, avoiding a one-cycle lag.
3. **Hysteresis FSM**: once the alarm is triggered, it persists until a Normal beat (class 0) arrives.

Additionally:

- **Calibration mode** (`mode_sel = 1`): while active, each Normal-labelled sample reduces the internal threshold of the heartbeat segmenter, adapting to a patient's baseline.
- **Test mode** (`force_class = 1`): the Decision Engine reads its input class directly from `ui_in[2:0]`, bypassing the SNN. This enables direct verification of the decision logic.

### Design decisions 

- **1x1 tile size**: the design fits in a single tile at 79.5% utilization, the size of the tile was imposed by the administrator of the CANELOS Tiny Tapeot workshop.
- **40 MHz clock**: nominal frequency.
- **Synchronous, single clock domain**: no CDC or asynchronous logic.

## How to test

The design is verified with a **cocotb** testbench in `test/`. Run:

```bash
cd test
make
```

The testbench exercises:

1. **Reset behavior** — verifies alarm and pattern outputs are 0 after reset.
2. **Hysteresis** — uses `force_class` to inject 3 consecutive Ventricular classifications, verifies the alarm activates, then injects a Normal beat and verifies the alarm clears.
3. **Calibration mode** — verifies the calibration path does not break the DUT.


Manual testing
To test with real hardware:

Connect an ECG signal source to ui_in[7:0] and uio_in[3:0].

Pulse uio_in[4] (sample_en) when a new sample is ready.

Observe uo_out[0] (alarm), uo_out[1] (pattern_detected), and uo_out[4:2] (class_out).

For a functional test without an ECG, set uio_in[6] (force_class) high and inject a class on ui_in[2:0].

## External hardware 

No external hardware is required to this project. The design is made to be tested with a standard ECG ADC or in standalone mode using the force_class test mode.

