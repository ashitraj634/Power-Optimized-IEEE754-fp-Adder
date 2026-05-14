# Power-Optimized IEEE-754 Single-Precision Floating-Point Adder

A power and area optimized 32-bit IEEE-754 floating-point adder implemented in Verilog and synthesized using Cadence Genus on a 45nm standard cell library. The design employs a dual-path micro-architecture with explicit operand isolation, a parallel tree-based Leading Zero Detector, and an early exception bypass — achieving a **10.9% reduction in dynamic switching power** and a **15% reduction in silicon area** over a monolithic baseline, with full timing closure at 200 MHz.

---

## The Problem with Monolithic Floating-Point Addition

IEEE-754 single-precision floating-point addition is significantly more expensive than integer addition. Every operation must execute the following sequence regardless of the actual operand values:

1. **Exponent Compare** — determine which operand is larger
2. **Alignment Shift** — right-shift the smaller mantissa to match exponents (up to 24 bits)
3. **Add / Subtract** — perform the mantissa operation
4. **Leading Zero Detection** — count leading zeros in the result
5. **Normalization Shift** — left-shift the result back into normalized form (up to 24 bits)
6. **Rounding** — apply round-to-nearest-even

The core inefficiency of a monolithic baseline is that both the alignment barrel-shifter and the normalization barrel-shifter are physically active on every single operation, regardless of whether large shifts are actually needed. In CMOS, dynamic power is consumed every time a transistor toggles — and these two blocks are responsible for the majority of toggle activity in the design.

---

## Architecture

### IEEE-754 Single-Precision Format

![IEEE-754 Format](docs/architecture/ieee754_format.png)

### Dual-Path Block Diagram

![Architecture Diagram](docs/architecture/architecture_diagram.png)

---

## Baseline Design — `fp_adder_baseline`

The baseline is a single unified pipeline. It uses an iterative `for` loop for normalization — scanning up to 27 bits sequentially to find the leading one. This creates a deep combinational chain that bottlenecks both timing and power.

**Key inefficiencies:**
- Full 24-bit alignment barrel-shifter active on every operation
- Full 24-bit normalization barrel-shifter (iterative loop) active on every operation
- No distinction between operand classes — all inputs treated identically

---

## Improved Design — `fp_dual_path_adder`

The improved design is built around a single mathematical observation: **the normalization requirement depends entirely on the exponent difference Δe = |expA − expB|**.

### Early Exception Bypass

Before any arithmetic begins, both operands are unpacked and checked for special cases. If either operand is zero, infinity, or NaN, an `early_bypass` flag is asserted and the canonical IEEE-754 result is forwarded directly to the output — bypassing the entire datapath.

```verilog
wire early_bypass = a_is_zero | b_is_zero | (expA == 8'd255) | (expB == 8'd255);
```

### Path Routing

For normal operands, the exponent difference and effective subtraction flag are computed. These jointly select one of two paths:

```verilog
wire is_close_path = eff_sub & (expDiff <= 8'd1) & ~early_bypass;
wire is_far_path   = ~is_close_path & ~early_bypass;
```

### FAR Path (`|Δe| > 1`)

When the exponent difference exceeds one, the operands differ by more than a factor of two in magnitude. Catastrophic cancellation — where subtraction of nearly equal values destroys all significant bits — is mathematically impossible in this regime.

- The smaller mantissa is right-shifted by min(Δe, 26) positions using a 50-bit extended alignment shifter
- Addition or subtraction is performed on 27-bit extended mantissa words
- Because the result magnitude is guaranteed to be close to the larger operand, **at most a 1-bit normalization adjustment is needed** — the entire 24-bit normalization barrel-shifter is eliminated

### CLOSE Path (`|Δe| ≤ 1`, effective subtraction only)

When two operands of opposite sign and nearly equal magnitude are subtracted, up to 24 leading zeros can appear in the result. The CLOSE path is purpose-built for this case:

- Because Δe ≤ 1, mantissa alignment requires at most a single 1-bit right-shift — the alignment barrel-shifter is eliminated entirely
- A **25-bit parallel priority-encoder LZD** counts leading zeros in the subtraction result in a single pass, synthesizing to a balanced logic tree rather than a sequential chain
- The result is left-shifted by the detected zero count and the exponent is decremented accordingly

### Explicit Operand Isolation

Even after path routing, the raw mantissa signals would propagate into the idle sub-datapath and cause unnecessary gate switching. RTL-level data barriers clamp the inputs of each idle path to zero:

```verilog
// FAR path: frozen when CLOSE is active
wire [23:0] far_manBig   = is_far_path ? manBig   : 24'd0;
wire [23:0] far_manSmall = is_far_path ? manSmall : 24'd0;

// CLOSE path: frozen when FAR is active
wire [23:0] close_manBig   = is_close_path ? manBig   : 24'd0;
wire [23:0] close_manSmall = is_close_path ? manSmall : 24'd0;
```

With inputs held at zero, the downstream gates in the idle path receive no transitions. Their activity factor α is driven to zero, directly eliminating dynamic power dissipation from those blocks.

### Shared Rounding Stage

Both paths drive a common Round-to-Nearest-Even (RNE) stage using three low-order GRS bits preserved throughout computation:

```
R_up = G · (R + S + LSB)
```

---

## Verification Methodology

Functional verification and activity profiling were performed using Cadence Xcelium and SimVision. A common testbench applied **1,000 randomized 32-bit input vectors** followed by four directed corner cases:

- `0 + 1` — zero operand bypass
- `1 + 0` — zero operand bypass
- `+∞ + 1` — infinity propagation
- `1 + (−1)` — catastrophic cancellation

A VCD dump was generated at every hierarchy level and fed into Cadence Genus during power analysis, providing gate-level toggle rates derived from actual simulated switching activity — rather than the tool's default 20% statistical estimate.

```verilog
$dumpfile("activity_profile.vcd");
$dumpvars(0, tb_fp_adder_core);
```

A structural wrapper (`fp_adder_wrapper.v`) placed 32-bit DFF register banks at the A, B, and RESULT ports to create a register-to-register timing path, enabling meaningful Static Timing Analysis on the purely combinational core.

**SDC Constraints (identical for both designs):**
- Clock: 200 MHz virtual clock, 5.0 ns period
- Input/Output delays: 0.5 ns at all register boundaries
- Transition time: 0.2 (normalized)
- Load capacitance: 80 (library units)

---

## Synthesis Results

Synthesized with Cadence Genus 21.14 targeting GPDK 45nm, `PVT_1P1V_0C (balanced_tree)`.

### Area

| Metric | Baseline | Improved | Change |
|---|---|---|---|
| Cell Count | 1,077 | 894 | **−17.0%** |
| Cell Area | 1978.8 µm² | 1682.3 µm² | **−15.0%** |
| Wrapper Total Area | 2569.8 µm² | 2273.3 µm² | −11.5% |

### Power

| Metric | Baseline | Improved | Change |
|---|---|---|---|
| Switching Power | 95.02 µW | 84.65 µW | **−10.9%** |
| Leakage Power | 1.063 µW | 0.941 µW | −11.5% |
| Internal Power | 233.08 µW | 242.84 µW | +4.2% |
| **Total Power** | **329.16 µW** | **328.43 µW** | −0.2% |

> The 4.2% increase in internal power arises from the additional capacitance of the dual-path routing multiplexers. The switching power reduction directly reflects the suppression of toggle activity through operand isolation.

### Timing

| Metric | Baseline | Improved |
|---|---|---|
| Critical Path Delay | 3218 ps | 3336 ps |
| Setup Slack (5 ns) | **+1669 ps** | **+1550 ps** |
| Timing Closure | MET ✓ | MET ✓ |

> The 118 ps (3.6%) timing penalty is attributable to the final 2-to-1 result multiplexer added to the critical path. Both designs have substantial positive slack, confirming safe operation at 200 MHz with margin to absorb process variation.

---

## Simulation Waveforms

**Baseline**

![Waveform Baseline](docs/waveforms/baseline/waveform_baseline.png)

**Improved — Overview**

![Waveform Improved](docs/waveforms/improved/waveform_improved_1.png)

**Improved — Signal Detail**

![Waveform Improved Detail](docs/waveforms/improved/waveform_improved_2.png)

---

## Synthesis Schematics (Cadence Genus)

**Baseline — `fp_adder_wrapper`**

![Schematic Baseline Overview](docs/schematics/baseline/schematic_baseline_overview.png)

![Schematic Baseline Zoomed](docs/schematics/baseline/schematic_baseline_zoomed1.png)

**Improved — `fp_dual_path_wrapper`**

![Schematic Improved Overview](docs/schematics/improved/schematic_improved_overview.png)

![Schematic Improved Zoomed](docs/schematics/improved/schematic_improved_zoomed1.png)

---

## Synthesis Report Screenshots

**Baseline**

![Power Report Baseline](docs/reports/baseline/power_report_baseline.png)

![Area Report Baseline](docs/reports/baseline/area_report_baseline.png)

![Timing Report Baseline](docs/reports/baseline/timing_report_baseline.png)

**Improved**

![Power Report Improved](docs/reports/improved/power_report_improved.png)

![Area Report Improved](docs/reports/improved/area_report_improved.png)

---

## Repository Structure

```
├── src/
│   ├── fp_adder_baseline.v              # Baseline single-path adder
│   └── fp_dual_path_adder.v             # Improved dual-path adder
├── testbench/
│   ├── tb_fp_adder_baseline.v           # Testbench for baseline
│   └── tb_fp_adder_core.v               # Testbench for dual-path
├── synthesis/
│   ├── baseline/
│   │   ├── reports/                     # Area, power, timing reports
│   │   └── scripts/                     # run_synth.tcl, constraints.sdc
│   └── improved/
│       ├── reports/
│       └── scripts/
└── docs/
    ├── paper.pdf                        # IEEE-format conference paper
    ├── project_report.pdf               # Full project report
    ├── architecture/                    # Block diagrams and format diagrams
    ├── waveforms/                       # SimVision simulation waveforms
    │   ├── baseline/
    │   └── improved/
    ├── schematics/                      # Cadence Genus schematic screenshots
    │   ├── baseline/
    │   └── improved/
    └── reports/                         # Synthesis report screenshots
        ├── baseline/
        └── improved/
```

---

## How to Run

**Simulate (Cadence Xcelium)**

```bash
# Baseline
xrun testbench/tb_fp_adder_baseline.v src/fp_adder_baseline.v -access +rwc -gui

# Improved
xrun testbench/tb_fp_adder_core.v src/fp_dual_path_adder.v -access +rwc -gui
```

**Synthesize (Cadence Genus)**

```bash
# Baseline
cd synthesis/baseline/scripts && genus -f run_synth.tcl

# Improved
cd synthesis/improved/scripts && genus -f run_synth.tcl
```
