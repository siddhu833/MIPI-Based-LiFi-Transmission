import os
import sys
from PIL import Image

def generate_sample_image(filename="sample_input.png", width=64, height=64):
    """Generates a sample color test pattern image if none provided."""
    img = Image.new("RGB", (width, height))
    pixels = img.load()
    for y in range(height):
        for x in range(width):
            r = int((x / width) * 255)
            g = int((y / height) * 255)
            b = int(((x + y) / (width + height)) * 255)
            pixels[x, y] = (r, g, b)
    img.save(filename)
    print(f"[Python] Generated sample test pattern image: {filename} ({width}x{height})")
    return filename

def image_to_mipi_raw10(image_path, output_hex_path):
    """Converts an image into MIPI CSI-2 RAW10 packet hex stream."""
    if not os.path.exists(image_path):
        generate_sample_image(image_path)

    img = Image.open(image_path).convert("L") # Convert to 8-bit grayscale for RAW10
    width, height = img.size

    # Adjust width to multiple of 4 (RAW10 requires 4 pixels per 5 bytes)
    if width % 4 != 0:
        width = (width // 4) * 4
        img = img.resize((width, height))

    print(f"[Python] Encoding image '{image_path}' ({width}x{height}) to MIPI RAW10...")

    hex_lines = []
    
    for y in range(height):
        # Line Header: SOT marker indicator
        hex_lines.append("SOT")
        
        # Calculate Payload Byte Count: 5 bytes per 4 pixels
        payload_bytes_count = (width // 4) * 5
        wc_lsb = payload_bytes_count & 0xFF
        wc_msb = (payload_bytes_count >> 8) & 0xFF
        data_id = 0x2B # RAW10
        ecc = 0x00      # Dummy ECC

        # 4 Header Bytes: DataID, WC_LSB, WC_MSB, ECC
        hex_lines.append(f"{data_id:02X}")
        hex_lines.append(f"{wc_lsb:02X}")
        hex_lines.append(f"{wc_msb:02X}")
        hex_lines.append(f"{ecc:02X}")

        # Payload Bytes
        row_pixels = [img.getpixel((x, y)) for x in range(width)]
        for i in range(0, width, 4):
            p0 = row_pixels[i]
            p1 = row_pixels[i+1]
            p2 = row_pixels[i+2]
            p3 = row_pixels[i+3]

            b0 = (p0 >> 2) & 0xFF
            b1 = (p1 >> 2) & 0xFF
            b2 = (p2 >> 2) & 0xFF
            b3 = (p3 >> 2) & 0xFF
            b4 = ((p3 & 0x03) << 6) | ((p2 & 0x03) << 4) | ((p1 & 0x03) << 2) | (p0 & 0x03)

            hex_lines.append(f"{b0:02X}")
            hex_lines.append(f"{b1:02X}")
            hex_lines.append(f"{b2:02X}")
            hex_lines.append(f"{b3:02X}")
            hex_lines.append(f"{b4:02X}")

        # 2 CRC Bytes
        hex_lines.append("12")
        hex_lines.append("34")
        
        # Line EOT marker
        hex_lines.append("EOT")

    os.makedirs(os.path.dirname(output_hex_path), exist_ok=True)
    with open(output_hex_path, "w") as f:
        for line in hex_lines:
            f.write(line + "\n")

    print(f"[Python] MIPI RAW10 hex stream written to: {output_hex_path}")

if __name__ == "__main__":
    img_path = sys.argv[1] if len(sys.argv) > 1 else "sample_input.png"
    out_hex = sys.argv[2] if len(sys.argv) > 2 else "tb/mipi_tx_stream.hex"
    image_to_mipi_raw10(img_path, out_hex)
