`timescale 1ns/1ps
// =============================================================================
// lifi_tx_top.v
// Top-Level Transmitter Module (TX FPGA / PYNQ Board)
//
// Receives D-PHY bytes from camera, passes through cut-through CSI-2 parser,
// frames with Preamble/Comma/Idle, encodes via 8b/10b, and serializes to 1-BIT LED.
// =============================================================================
module lifi_tx_top #(
    parameter [1:0] TARGET_VC = 2'b00
)(
    input  wire       clk_phy,       // D-PHY Byte / Symbol Clock (200 MHz)
    input  wire       clk_bit,       // 10x Bit Clock (2.0 GHz for 1-bit serializing)
    input  wire       rst_n,

    // D-PHY Camera Inputs
    input  wire [7:0] phy_byte,
    input  wire       phy_valid,
    input  wire       phy_sot,
    input  wire       phy_eot,

    // Single-Bit Optical Output to Laser / LED Driver
    output reg        led_tx_serial,
    output wire       tx_active
);

    // 1. Cut-Through CSI-2 Receiver
    wire [7:0] llp_data;
    wire       llp_valid;
    wire       llp_last;

    csi2_rx_llp_sf u_llp (
        .clk(clk_phy),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .m_axis_tdata(llp_data),
        .m_axis_tvalid(llp_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(llp_last)
    );

    // 2. Li-Fi Framer (Preamble, K.28.5 SOT, K.28.1 EOT/Idle)
    wire [7:0] framer_data;
    wire       framer_k;
    wire       framer_valid;

    lifi_framer u_framer (
        .clk(clk_phy),
        .rst_n(rst_n),
        .phy_byte(llp_data),
        .phy_valid(llp_valid),
        .phy_sot(phy_sot),
        .phy_eot(phy_eot),
        .data_out(framer_data),
        .k_out(framer_k),
        .valid_out(framer_valid)
    );

    // 3. IBM 8b/10b Encoder
    wire [9:0] enc_10b;
    wire       enc_valid;

    encoder_8b10b u_encoder (
        .clk(clk_phy),
        .rst_n(rst_n),
        .d_in(framer_data),
        .k_in(framer_k),
        .valid_in(framer_valid),
        .q_out(enc_10b),
        .valid_out(enc_valid),
        .rd_out()
    );

    // 4. Parallel-In Serial-Out (PISO) Serializer (8b/10b standard: bit 'a' [bit 0] first)
    reg [9:0] shift_reg;
    reg [3:0] bit_cnt;

    always @(posedge clk_bit or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg     <= 10'b0;
            bit_cnt       <= 4'd0;
            led_tx_serial <= 1'b0;
        end else begin
            if (bit_cnt == 4'd0 || bit_cnt == 4'd10) begin
                if (enc_valid) begin
                    shift_reg     <= enc_10b;
                    led_tx_serial <= enc_10b[0]; // Transmit bit 'a' (LSB) first per 8b/10b spec
                    bit_cnt       <= 4'd1;
                end else begin
                    led_tx_serial <= 1'b0;
                    bit_cnt       <= 4'd0;
                end
            end else begin
                led_tx_serial <= shift_reg[bit_cnt];
                bit_cnt       <= bit_cnt + 1'b1;
            end
        end
    end

    assign tx_active = (bit_cnt > 0);

endmodule
