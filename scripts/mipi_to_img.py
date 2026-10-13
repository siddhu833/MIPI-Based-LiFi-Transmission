import os
import sys
from PIL import Image

def mipi_hex_to_image(hex_path="tb/mipi_rx_pixels.hex", output_image_path="output_reconstructed.png", width=64, height=64):
    """Reads reconstructed pixel hex values from Verilog simulation and saves PNG image."""
    if not os.path.exists(hex_path):
        print(f"[Error] Hex file not found: {hex_path}")
        return

    pixels = []
    with open(hex_path, "r") as f:
        for line in f:
            val_str = line.strip()
            if val_str:
                try:
                    val = int(val_str, 16)
                    # Extract 24-bit RGB (or grayscale)
                    r = (val >> 16) & 0xFF
                    g = (val >> 8) & 0xFF
                    b = val & 0xFF
                    pixels.append((r, g, b))
                except ValueError:
                    continue

    print(f"[Python] Read {len(pixels)} reconstructed pixels from {hex_path}")

    # Determine image dimensions
    num_pixels = len(pixels)
    if num_pixels == 0:
        print("[Error] No pixels found in hex file!")
        return

    img = Image.new("RGB", (width, height))
    img.putdata(pixels[:width*height])

    img.save(output_image_path)
    print(f"[Python] Reconstructed image saved successfully: {output_image_path} ({width}x{height})")

def compare_with_reference(hex_path, ref_image_path, width, height):
    """Pixel-exact check: RX pixels must equal the grayscale of the reference image."""
    ref = Image.open(ref_image_path).convert("L").resize((width, height))
    exp = list(ref.getdata())
    got = []
    with open(hex_path) as f:
        for line in f:
            if line.strip():
                got.append(int(line.strip(), 16))
    ok = sum(1 for e, g in zip(exp, got) if g == e * 0x010101)
    status = "PASS" if (ok == len(exp) and len(got) == len(exp)) else "FAIL"
    print(f"[Python] Compare: {ok}/{len(exp)} pixels match, received {len(got)} -> {status}")
    return status == "PASS"

if __name__ == "__main__":
    hex_in = sys.argv[1] if len(sys.argv) > 1 else "tb/mipi_rx_pixels.hex"
    img_out = sys.argv[2] if len(sys.argv) > 2 else "output_reconstructed.png"
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 64
    h = int(sys.argv[4]) if len(sys.argv) > 4 else 64
    mipi_hex_to_image(hex_in, img_out, w, h)
    if len(sys.argv) > 5:
        sys.exit(0 if compare_with_reference(hex_in, sys.argv[5], w, h) else 1)
