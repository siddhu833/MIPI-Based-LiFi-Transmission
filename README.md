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
# 1. Self-checking system test (one RAW10 packet, 4 pixels, ECC/CRC clean) -> prints PASS/FAIL
iverilog -o sim_sys.vvp -s tb_lifi_system tb/tb_lifi_system.v rtl/lifi_system_top.v rtl/tx/*.v rtl/rx/*.v rtl/common/*.v
vvp sim_sys.vvp

# 2. 64x64 image through the 1-bit link, compared pixel by pixel
python scripts/img_to_mipi.py data/sample_input.png tb/mipi_tx_stream.hex
iverilog -o sim_img.vvp -s tb_lifi_image_demo tb/tb_lifi_image_demo.v rtl/lifi_system_top.v rtl/tx/*.v rtl/rx/*.v rtl/common/*.v
vvp sim_img.vvp
python scripts/mipi_to_img.py tb/mipi_rx_pixels.hex out.png 64 64 data/sample_input.png   # prints PASS/FAIL
```

## Status
* Image loopback: 64x64 image, **4096/4096 pixels match** the grayscale reference, 0 ECC errors, 0 CRC errors.
* Error detection checked by corrupting the input: a bad payload byte raises `crc_error` (and the
  compare script reports FAIL); a 1-bit header error is corrected by the ECC and the image still matches.
* `tb_lifi_tx` only prints the TX side and is not self-checking.
* Header ECC uses the same parity equations as `rtl/common/csi2_ecc_rx.v`; they have not been
  checked against official MIPI test vectors.
* Test images are 8-bit grayscale sent as RAW10 (sample << 2); RGB888 and RAW8 pass-through paths exist
  but are not covered by a testbench.
* Not done: lint/CDC sign-off for this design, synthesis/timing, hardware bring-up (the optical
  front end is not part of the RTL). Clock ratio is assumed exactly 10:1 (`clk_bit` = 10 x `clk_phy`),
  as from one MMCM; the aligner holds each word for one `clk_phy` period instead of using a CDC pulse.

## Fixes made while bringing up the image loopback
1. TX sent each 10-bit symbol LSB first while the RX/decoder expect `a` (bit 9) first -> now MSB first.
2. Aligner rewritten: comma found in the last 7 received bits marks the symbol boundary; the word is
   held stable for one symbol period (the old 1-bit-clock valid pulse was lost crossing to `clk_phy`).
3. Decoder: `y=1` and `y=6` shared a code, and K28.x with RD+ needs the complemented `fghj` field.
4. ECC/CRC checker: only starts a header after the K28.5 comma (the 0x55 preamble was parsed as a header),
   now emits all 3 header bytes (DI, WC lsb, WC msb), and flags `tlast` on the last payload byte.
5. Pixel unpacker rewritten with back-pressure (the old one dropped words and corrupted its buffer);
   FIFO -> parser -> unpacker now use ready signals.
6. `img_to_mipi.py` now writes real header ECC and payload CRC-16 instead of dummy values, and the
   10-bit samples are the 8-bit gray value << 2 so the receiver's top 8 bits equal the gray value.
7. Removed two stale testbenches (`tb_csi2_rx_ecc_crc`, `tb_pixel_unpack`) written for older module ports.
