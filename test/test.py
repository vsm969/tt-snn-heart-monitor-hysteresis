# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
#
# Testbench para tt_um_arrhythmia_detector
# Modificaciones Copyright (c) 2026 Vicente Antonio San Martin Fuentes

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


CLK_PERIOD_US = 0.025  # 25 ns -> 40 MHz


async def reset_dut(dut):
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


async def send_forced_class(dut, class_val, mode_sel=0):
    """Inyecta una clase por el modo force_class."""
    dut.ui_in.value = class_val & 0x7
    uio = (1 << 6) | (1 << 4)  # force_class=1, sample_en=1
    if mode_sel:
        uio |= (1 << 5)
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 1)
    uio &= ~(1 << 4)  # sample_en=0
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_reset_state(dut):
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)
    uo_val = dut.uo_out.value.to_unsigned()
    alarm   = (uo_val >> 0) & 1
    pattern = (uo_val >> 1) & 1
    dut._log.info(f"Reset: alarm={alarm}, pattern={pattern}")
    assert alarm == 0
    assert pattern == 0


@cocotb.test()
async def test_hysteresis_3_anomalies(dut):
    """3 anomalias consecutivas activan alarma; Normal la limpia."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)
    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 0, "2 anomalias no deben disparar"

    await send_forced_class(dut, 2)
    uo = dut.uo_out.value.to_unsigned()
    assert ((uo >> 0) & 1) == 1, "3 anomalias deben disparar la alarma"
    assert ((uo >> 1) & 1) == 1, "pattern_detected debe activarse"

    await send_forced_class(dut, 0)
    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 0, "Normal debe limpiar la alarma"
    dut._log.info("Histeresis verificada correctamente")


@cocotb.test()
async def test_calibration_mode(dut):
    """Modo calibracion no debe romper el DUT."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(4):
        await send_forced_class(dut, 0, mode_sel=1)

    # Volver a modo inferencia
    await send_forced_class(dut, 2)
    dut._log.info("Calibracion ejecutada sin crash")


@cocotb.test()
async def test_fusion_does_not_clear_alarm(dut):
    """La clase Fusión (3) no debe limpiar la alarma."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Activar alarma con 3 ventriculares
    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)
    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 1

    # Enviar clase Fusión (no debe limpiar)
    await send_forced_class(dut, 3)
    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 1, \
        "La clase Fusión no debe limpiar la alarma"

    # Ahora sí, Normal limpia
    await send_forced_class(dut, 0)
    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 0



@cocotb.test()
async def test_more_than_3_anomalies(dut):
    """4 o más anomalías mantienen la alarma activa."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    for _ in range(5):
        await send_forced_class(dut, 2)

    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 1, \
        "La alarma debe mantenerse activa con 5 anomalías"



@cocotb.test()
async def test_interrupted_sequence(dut):
    """2 anomalías, luego Normal, luego 2 anomalías NO debe activar la alarma."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)
    await send_forced_class(dut, 0)   # Interrumpe
    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)

    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 0, \
        "El contador debe haberse reseteado con el Normal"



@cocotb.test()
async def test_all_anomaly_classes(dut):
    """Las clases 1, 2 y 4 cuentan como anomalías."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Mezcla de clases anómalas
    await send_forced_class(dut, 1)  # Supraventricular
    await send_forced_class(dut, 2)  # Ventricular
    await send_forced_class(dut, 4)  # Desconocido

    assert ((dut.uo_out.value.to_unsigned() >> 0) & 1) == 1, \
        "Mezcla de 1, 2, 4 debe activar la alarma"



@cocotb.test()
async def test_pattern_pulse_width(dut):
    """pattern_detected debe ser un pulso de un solo ciclo."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)
    await send_forced_class(dut, 2)

    # pattern_detected debe estar alto justo en el ciclo de la 3ra anomalía
    assert ((dut.uo_out.value.to_unsigned() >> 1) & 1) == 1

    # Esperar varios ciclos y verificar que bajó
    await ClockCycles(dut.clk, 5)
    assert ((dut.uo_out.value.to_unsigned() >> 1) & 1) == 0, \
        "pattern_detected debe bajar después del pulso"


@cocotb.test()
async def test_calibration_reduces_threshold(dut):
    """La calibración debe reducir el umbral interno.
    
    Nota: este test solo corre en simulación RTL, no en gate-level,
    porque la jerarquía interna (u_decision) se aplana durante la síntesis.
    """
    # Detectar si estamos en gate-level
    # En gate-level, el netlist está aplanado y no existe u_decision
    try:
        _ = dut.user_project.u_decision
    except AttributeError:
        dut._log.info("Gate-level simulation detected: skipping hierarchical test")
        return

    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Acceder al registro interno del Decision Engine
    umbral_inicial = dut.user_project.u_decision.threshold_out.value.to_unsigned()

    # Modo calibración + 4 clases Normal
    for _ in range(4):
        await send_forced_class(dut, 0, mode_sel=1)

    umbral_final = dut.user_project.u_decision.threshold_out.value.to_unsigned()
    assert umbral_final < umbral_inicial, \
        f"El umbral debe reducirse (era {umbral_inicial}, ahora {umbral_final})"