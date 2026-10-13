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

if __name__ == "__main__":
    hex_in = sys.argv[1] if len(sys.argv) > 1 else "tb/mipi_rx_pixels.hex"
    img_out = sys.argv[2] if len(sys.argv) > 2 else "output_reconstructed.png"
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 64
    h = int(sys.argv[4]) if len(sys.argv) > 4 else 64
    mipi_hex_to_image(hex_in, img_out, w, h)
