`timescale 1ns/1ps
// =============================================================================
// lifi_system_top.v
// Full System Top-Level Module (Connecting Li-Fi Transmitter & Receiver)
//
// Links lifi_tx_top and lifi_rx_top STRICTLY over a 1-BIT serial light link!
// =============================================================================
module lifi_system_top #(
    parameter [1:0] TARGET_VC = 2'b00
)(
    input  wire        clk_phy,       // D-PHY / TX symbol clock (200 MHz)
    input  wire        clk_bit,       // 10x Serial Bit Clock (2.0 GHz)
    input  wire        clk_sys,       // FPGA RX system clock (100 MHz)
    input  wire        rst_n,

    // Camera Input Ports (TX)
    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,
    input  wire        phy_sot,
    input  wire        phy_eot,

    // Reconstructed Pixel Output Ports (RX)
    output wire [23:0] px_out,
    output wire        px_valid,
    output wire        px_last,

    // System Status & Error Flags
    output wire        tx_active,
    output wire        rx_lock,
    output wire        ecc_ok,
    output wire        ecc_corrected,
    output wire        ecc_error,
    output wire        crc_error,
    output wire [7:0]  rx_data_id
);

    // Single-Bit Wireless Optical Link Wire (LED light -> Photodiode TIA)
    wire optical_serial_link;

    // Instantiate Li-Fi Transmitter Top
    lifi_tx_top #(
        .TARGET_VC(TARGET_VC)
    ) u_tx_top (
        .clk_phy(clk_phy),
        .clk_bit(clk_bit),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .phy_sot(phy_sot),
        .phy_eot(phy_eot),
        .led_tx_serial(optical_serial_link), // STRICTLY 1-BIT OUTPUT!
        .tx_active(tx_active)
    );

    // Instantiate Li-Fi Receiver Top
    lifi_rx_top #(
        .TARGET_VC(TARGET_VC)
    ) u_rx_top (
        .clk_bit(clk_bit),
        .clk_cdr(clk_phy),
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .pd_rx_serial(optical_serial_link), // STRICTLY 1-BIT INPUT!
        .px_out(px_out),
        .px_valid(px_valid),
        .px_last(px_last),
        .rx_lock(rx_lock),
        .ecc_ok(ecc_ok),
        .ecc_corrected(ecc_corrected),
        .ecc_error(ecc_error),
        .crc_error(crc_error),
        .rx_data_id(rx_data_id)
    );

endmodule
