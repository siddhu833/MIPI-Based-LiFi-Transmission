# Li-Fi MIPI CSI-2 Video Transmission System — Engineering Handover Guide

This repository contains the complete Verilog RTL implementation, simulation testbenches, Python image encoding/decoding utilities, and Vivado packaging scripts for transmitting MIPI CSI-2 camera video (RAW10 / RGB888) over a high-speed **1-BIT optical wireless link (Li-Fi)**.

---

## 1. Project Directory Structure

```
lifi_csi2_project/
├── rtl/
│   ├── tx/                           # Transmitter Modules (Target: PYNQ-Z1/Z2)
│   │   ├── lifi_tx_top.v             # Master TX Top Wrapper (1-BIT serial output)
│   │   ├── csi2_rx_ecc_crc.v         # Cut-Through CSI-2 Receiver Passthrough
│   │   ├── lifi_framer.v             # Preamble + K.28.5 Comma + K.28.1 Idle Framer
│   │   └── encoder_8b10b.v           # IBM 8b/10b Encoder
│   │
│   ├── rx/                           # Receiver Modules (Target: Zedboard)
│   │   ├── lifi_rx_top.v             # Master RX Top Wrapper (1-BIT serial input)
│   │   ├── lifi_rx_aligner.v         # 10-bit Symbol Aligner (K.28.5 Comma Detection)
│   │   ├── decoder_8b10b.v           # 8b/10b Decoder with error checks
│   │   ├── ecc_crc_checker.v         # Cut-Through Header ECC Correction & Payload CRC
│   │   ├── axis_asyncc_fifo.v        # 8-bit @ clk_cdr -> 24-bit @ clk_sys CDC Async FIFO
│   │   ├── mipi_hdr_parser.v         # 24-bit MIPI Header Parser (data_id & word_count)
│   │   └── pixel_unpack.v            # 24-bit Pixel Unpacker (RAW10 / RGB888 / RAW8)
│   │
│   ├── common/                       # Shared CDC & Primitive Modules
│   │   ├── asyncc_fifo.v             # Core Dual-Clock Asynchronous FIFO
│   │   ├── 2ff_sync.v                # 2-Flip-Flop Synchronizer
│   │   ├── w_ptr_handler.v           # Gray-code Write Pointer Handler
│   │   ├── rd_ptr_hdlr.v             # Gray-code Read Pointer Handler
│   │   ├── csi2_ecc_rx.v             # Hamming ECC Decoder Matrix
│   │   ├── crc.v                     # CRC-16 (0x1021) Accumulator
│   │   ├── sync_fifo.v               # Synchronous FIFO Primitive
│   │   └── D_flipflop.v              # D Flip-Flop Primitive
│   │
│   └── lifi_system_top.v             # Top-Level System Wrapper (TX + 1-BIT Link + RX)
│
├── tb/                               # Simulation Testbenches
│   ├── tb_lifi_system.v              # Master 1-Bit System Simulation (RAW10 & RGB888)
│   ├── tb_lifi_image_demo.v          # Python Image Verification Simulation
│   └── tb_lifi_tx.v                  # Standalone TX Testbench
│
└── scripts/                          # Automation & Conversion Utilities
    ├── img_to_mipi.py                # Image -> MIPI RAW10 Hex Packets Converter
    ├── mipi_to_img.py                # Hex Output -> PNG Image Reconstructor
    ├── package_llp_ip.tcl            # Vivado Tcl script to package CSI-2 & FIFO IPs
    └── package_ip.tcl                # Vivado Tcl script to package Unpacker IP
```

---

## 2. Clocking Architecture & 1-Bit Interface Specs

| Signal | Clock Domain | Description | Target Hardware Pin |
|---|---|---|---|
| **`clk_phy`** | 10 MHz – 200 MHz | D-PHY Byte / Symbol Clock | PYNQ Camera RX Byte Clock / Clock Wizard |
| **`clk_bit`** | 100 MHz – 2.0 GHz | 10× Serial Bit Clock | OSERDESE2 / ISERDESE2 Clock |
| **`clk_sys`** | 100 MHz | FPGA System / Display / Frame Buffer Clock | Zedboard System Clock (`100 MHz`) |
| **`led_tx_serial`** | `clk_bit` | **STRICTLY 1-BIT** Serial Stream to Laser Driver | PMOD / FMC Output Pin (Laser Diode) |
| **`pd_rx_serial`** | `clk_bit` | **STRICTLY 1-BIT** Serial Stream from Photodiode | PMOD / FMC Input Pin (Photodiode TIA) |
| **`px_out[23:0]`** | `clk_sys` | Reconstructed RGB24 / Grayscale Pixel Data | Frame Buffer AXI Stream / VDMA |
| **`px_valid`** | `clk_sys` | High when `px_out` contains a valid pixel | Frame Buffer Valid |
| **`px_last`** | `clk_sys` | High on final pixel of video line | Frame Buffer TLAST |
| **`crc_error`** | `clk_sys` | Asserted post-hoc if packet CRC fails | Frame Buffer Drop Request Signal |

---

## 3. How to Run Simulation Verification

### Using Icarus Verilog (`iverilog`):

```bash
# 1. Master System Simulation (RAW10 & RGB888 verification over 1-bit optical link)
iverilog -o sim_sys.vvp tb/tb_lifi_system.v rtl/lifi_system_top.v rtl/tx/*.v rtl/rx/*.v rtl/common/*.v
vvp sim_sys.vvp

# 2. End-to-End Image Transmission Verification
python scripts/img_to_mipi.py sample_input.png tb/mipi_tx_stream.hex
iverilog -o sim_img.vvp tb/tb_lifi_image_demo.v rtl/lifi_system_top.v rtl/tx/*.v rtl/rx/*.v rtl/common/*.v
vvp sim_img.vvp
python scripts/mipi_to_img.py tb/mipi_rx_pixels.hex output_reconstructed.png 64 64
```

---

## 4. Vivado Deployment & Hardware Wiring Instructions

1. **TX Board (PYNQ-Z1 / PYNQ-Z2)**:
   - Connect Raspberry Pi Camera v2 to native MIPI CSI-2 connector.
   - Instantiate `lifi_tx_top.v` in Vivado Block Design.
   - Connect **`led_tx_serial` (1-bit output)** to PMOD pin connected to Laser Diode driver circuit.

2. **RX Board (Zedboard)**:
   - Connect Photodiode + Transimpedance Amplifier (TIA) comparator output to Zedboard PMOD pin.
   - Instantiate `lifi_rx_top.v` in Vivado Block Design.
   - Connect PMOD input pin to **`pd_rx_serial` (1-bit input)** of `lifi_rx_top.v`.
   - Connect `px_out[23:0]`, `px_valid`, and `px_last` to AXI VDMA / HDMI / VGA controller for display.
