# MIPI CSI-2 over Li-Fi (1-bit optical link) - TX and RX

Verilog design that carries MIPI CSI-2 camera packets over a **single-bit serial
(Li-Fi) link**: the transmitter frames and 8b/10b-encodes the CSI-2 byte stream, and the
receiver recovers symbols, checks ECC/CRC, crosses clock domains and unpacks pixels.

```
 CSI-2 bytes -> [csi2_rx_ecc_crc] -> [lifi_framer] -> [encoder_8b10b] -> serializer -> 1-bit LED/laser
                                                                                        |  optical link
 px_out/valid/last <- [pixel_unpack] <- [axis async FIFO] <- [ecc_crc_checker] <- [decoder_8b10b] <- [lifi_rx_aligner] <- 1-bit photodiode
```

## Structure
| Path | Contents |
|---|---|
| `rtl/tx/` | `lifi_tx_top` (1-bit serial out), cut-through CSI-2 passthrough, `lifi_framer` (preamble + K28.5 comma + K28.1 idle), `encoder_8b10b` |
| `rtl/rx/` | `lifi_rx_top` (1-bit serial in), `lifi_rx_aligner` (comma detect, 10-bit alignment), `decoder_8b10b` (with error checks), `ecc_crc_checker` (header ECC, payload CRC-16), `axis_asyncc_fifo` (8-bit `clk_cdr` -> 24-bit `clk_sys`), `mipi_hdr_parser`, `pixel_unpack` (RAW10 / RGB888 / RAW8) |
| `rtl/common/` | Gray-code async FIFO (`asyncc_fifo`, `w_ptr_handler`, `rd_ptr_hdlr`, `2ff_sync`), `csi2_ecc_rx`, `crc`, `sync_fifo`, `D_flipflop` |
| `rtl/lifi_system_top.v` | TX + 1-bit link + RX |
| `tb/` | `tb_lifi_tx` (TX only), `tb_lifi_system` (end to end), `tb_lifi_image_demo` (Python image in/out), `tb_csi2_rx_ecc_crc`, `tb_pixel_unpack` |
| `scripts/` | `img_to_mipi.py`, `mipi_to_img.py`, Vivado IP packaging Tcl |
| `docs/ENGINEERING_HANDOVER.md` | clocking table and board wiring notes (PYNQ TX, Zedboard RX) |

## Run (Icarus Verilog)
```
iverilog -o sim_sys.vvp tb/tb_lifi_system.v rtl/lifi_system_top.v rtl/tx/*.v rtl/rx/*.v rtl/common/*.v
vvp sim_sys.vvp
```
Image demo: `python scripts/img_to_mipi.py data/sample_input.png tb/mipi_tx_stream.hex`, then
compile `tb/tb_lifi_image_demo.v` the same way, run it, then
`python scripts/mipi_to_img.py tb/mipi_rx_pixels.hex out.png 64 64`.

## Status (honest)
* All RTL and the TX, system and image testbenches compile and run to completion.
* `tb_lifi_tx` and `tb_lifi_system` are **print-and-inspect** testbenches, not self-checking.
* The 64x64 image loopback is **not yet bit-exact**: the demo currently captures 4401
  pixel words for a 4096-pixel image and the reconstructed picture does not match the input.
  Debugging the RX alignment / packet boundary handling is the open item.
* Not yet done: lint/CDC sign-off for this design, synthesis/timing, hardware bring-up
  (the optical front end is not part of the RTL).
