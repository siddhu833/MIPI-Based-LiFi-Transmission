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

def csi2_ecc(di, wc):
    """6-bit header ECC, same parity equations as rtl/common/csi2_ecc_rx.v.
    data = {WC[13:0] padded, WC[7:0], DI} as seen by the receiver (bits 0..21)."""
    d = di | ((wc & 0xFF) << 8) | (((wc >> 8) & 0x3F) << 16)
    def par(bits):
        v = 0
        for b in bits:
            v ^= (d >> b) & 1
        return v
    e0 = par([0,1,3,4,6,8,10,11,13,15,17,19,21,23,25])
    e1 = par([0,2,3,5,6,9,10,12,13,16,17,20,21,24,25])
    e2 = par([1,2,3,7,8,9,10,14,15,16,17,22,23,24,25])
    e3 = par([4,5,6,7,8,9,10,18,19,20,21,22,23,24,25])
    e4 = par(range(11, 26))
    e5 = par(range(0, 20))
    return e0 | (e1 << 1) | (e2 << 2) | (e3 << 3) | (e4 << 4) | (e5 << 5)

def crc16_1021(data):
    """CRC-16, poly 0x1021, seed 0xFFFF, bits taken LSB first (matches rtl/common/crc.v)."""
    crc = 0xFFFF
    for byte in data:
        for i in range(8):
            fb = ((byte >> i) & 1) ^ ((crc >> 15) & 1)
            crc = (crc << 1) & 0xFFFF
            if fb:
                crc ^= 0x1021
    return crc

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
        ecc = csi2_ecc(data_id, payload_bytes_count)

        # 4 Header Bytes: DataID, WC_LSB, WC_MSB, ECC
        hex_lines.append(f"{data_id:02X}")
        hex_lines.append(f"{wc_lsb:02X}")
        hex_lines.append(f"{wc_msb:02X}")
        hex_lines.append(f"{ecc:02X}")

        # Payload Bytes
        payload = []
        row_pixels = [img.getpixel((x, y)) for x in range(width)]
        for i in range(0, width, 4):
            p0 = row_pixels[i]
            p1 = row_pixels[i+1]
            p2 = row_pixels[i+2]
            p3 = row_pixels[i+3]

            # 8-bit grayscale -> 10-bit sample (<<2), so the RX top 8 bits == the gray value
            q0, q1, q2, q3 = (p0 << 2), (p1 << 2), (p2 << 2), (p3 << 2)
            b0 = (q0 >> 2) & 0xFF
            b1 = (q1 >> 2) & 0xFF
            b2 = (q2 >> 2) & 0xFF
            b3 = (q3 >> 2) & 0xFF
            b4 = ((q3 & 0x03) << 6) | ((q2 & 0x03) << 4) | ((q1 & 0x03) << 2) | (q0 & 0x03)
            payload += [b0, b1, b2, b3, b4]

        for b in payload:
            hex_lines.append(f"{b:02X}")

        # 2 CRC bytes over the payload (LSB first)
        crc = crc16_1021(payload)
        hex_lines.append(f"{crc & 0xFF:02X}")
        hex_lines.append(f"{(crc >> 8) & 0xFF:02X}")
        
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
