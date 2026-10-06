# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
#
# Testbench adaptado para tt_um_arrhythmia_detector
# Modificaciones Copyright (c) 2026 [Tu Nombre]

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


CLK_PERIOD_US = 0.02  # 20 ns -> 50 MHz


async def reset_dut(dut):
    """Aplica reset y deja el DUT listo para operar."""
    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value  = 1
    await ClockCycles(dut.clk, 2)


async def send_sample(dut, adc_value, sample_en=True, mode_sel=0):
    """Envía una muestra de 12 bits al DUT."""
    dut.ui_in.value  = adc_value & 0xFF
    uio = (adc_value >> 8) & 0x0F
    if sample_en:
        uio |= (1 << 4)
    if mode_sel:
        uio |= (1 << 5)
    dut.uio_in.value = uio
    await ClockCycles(dut.clk, 1)
    dut.uio_in.value = uio & ~(1 << 4)
    await ClockCycles(dut.clk, 1)


@cocotb.test()
async def test_reset_state(dut):
    """Tras el reset, la alarma y el detector de patrón deben estar en 0."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Usar to_unsigned() para evitar DeprecationWarning
    uo_val = dut.uo_out.value.to_unsigned()
    alarm   = (uo_val >> 0) & 1
    pattern = (uo_val >> 1) & 1
    cls     = (uo_val >> 2) & 0x7

    dut._log.info(f"Reset state: alarm={alarm}, pattern={pattern}, class={cls}")

    assert alarm == 0, "La alarma debe iniciar en 0"
    assert pattern == 0, "El detector de patrón debe iniciar en 0"
    # Nota: no verificamos la clase porque el diseño original no la
    # inicializa en 0. Puede ser 7 (desconocido) u otro valor.


@cocotb.test()
async def test_wiring_stability(dut):
    """Envía algunas muestras y verifica que el DUT no crashee."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for i in range(10):
        await send_sample(dut, adc_value=1000 + i * 50, sample_en=True)

    dut._log.info("10 muestras procesadas sin crash")


@cocotb.test()
async def test_mode_sel_does_not_break(dut):
    """El modo calibración no debe romper el DUT."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    for i in range(5):
        await send_sample(dut, adc_value=1000, sample_en=True, mode_sel=1)

    for i in range(5):
        await send_sample(dut, adc_value=1000, sample_en=True, mode_sel=0)

    dut._log.info("Modo calibración ejecutado sin crash")

@cocotb.test()
async def test_forced_class_hysteresis(dut):
    """Verifica la lógica de histéresis forzando clases directamente."""
    clock = Clock(dut.clk, CLK_PERIOD_US, unit="us")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Función auxiliar para enviar una clase forzada
    async def send_forced_class(class_val):
        # Activar modo test (uio[6]=1) y sample_en (uio[4]=1)
        # Poner la clase en ui_in[2:0]
        dut.ui_in.value = class_val & 0x7
        dut.uio_in.value = (1 << 6) | (1 << 4)  # force_class=1, sample_en=1
        await ClockCycles(dut.clk, 1)
        # Desactivar sample_en
        dut.uio_in.value = (1 << 6)
        await ClockCycles(dut.clk, 1)

    # 1. Enviar 2 clases anómalas (Ventricular = 2)
    await send_forced_class(2)
    await send_forced_class(2)
    # La alarma no debería activarse todavía
    uo_val = dut.uo_out.value.to_unsigned()
    alarm = (uo_val >> 0) & 1
    assert alarm == 0, "La alarma no debe activarse con 2 anomalías"
    dut._log.info("2 anomalías: alarma en 0")

    # 2. Enviar la tercera anomalía
    await send_forced_class(2)
    # La alarma debería activarse
    uo_val = dut.uo_out.value.to_unsigned()
    alarm = (uo_val >> 0) & 1
    pattern = (uo_val >> 1) & 1
    assert alarm == 1, "La alarma debe activarse con 3 anomalías consecutivas"
    assert pattern == 1, "El detector de patrón debe activarse"
    dut._log.info("3 anomalías: alarma y patrón en 1")

    # 3. Enviar una clase normal (Normal = 0)
    await send_forced_class(0)
    # La alarma debería limpiarse
    uo_val = dut.uo_out.value.to_unsigned()
    alarm = (uo_val >> 0) & 1
    assert alarm == 0, "La alarma debe limpiarse con una clase Normal"
    dut._log.info("Normal después de anomalías: alarma limpiada")




        









