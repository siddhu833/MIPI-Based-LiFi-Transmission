`timescale 1ns/1ps
// =============================================================================
// lifi_rx_top.v
// Top-Level Receiver Module (RX FPGA / Zedboard)
//
// Receives strictly 1-BIT optical serial data from photodiode comparator,
// aligns on K.28.5 Comma on clk_bit, decodes via 8b/10b, performs cut-through ECC/CRC,
// and unpacks RGB24 pixels.
// =============================================================================
module lifi_rx_top #(
    parameter [1:0] TARGET_VC = 2'b00
)(
    input  wire        clk_bit,        // 10x Serial Bit Clock (2.0 GHz)
    input  wire        clk_cdr,        // Recovered Optical Symbol Clock (200 MHz)
    input  wire        clk_sys,        // FPGA System Clock (100 MHz)
    input  wire        rst_n,

    // Single-Bit Input from Photodiode TIA Receiver
    input  wire        pd_rx_serial,

    // Pixel Output to Frame Buffer / Display Controller
    output wire [23:0] px_out,
    output wire        px_valid,
    output wire        px_last,

    // Status & Error Flags
    output wire        rx_lock,
    output wire        ecc_ok,
    output wire        ecc_corrected,
    output wire        ecc_error,
    output wire        crc_error,      // Post-hoc flag for Frame Buffer controller
    output wire [7:0]  rx_data_id
);

    // 1. 10-bit Symbol Aligner (K.28.5 Comma Detection on clk_bit -> clk_cdr)
    wire [9:0] aligned_10b;
    wire       aligned_valid;

    lifi_rx_aligner u_aligner (
        .clk_bit(clk_bit),
        .clk_cdr(clk_cdr),
        .rst_n(rst_n),
        .pd_rx_serial(pd_rx_serial),
        .aligned_10b_out(aligned_10b),
        .aligned_valid(aligned_valid),
        .aligned_lock(rx_lock)
    );

    // 2. 8b/10b Decoder
    wire [7:0] dec_8b;
    wire       dec_k;
    wire       dec_valid;
    wire       code_err, disp_err;

    decoder_8b10b u_decoder (
        .clk(clk_cdr),
        .rst_n(rst_n),
        .d_in(aligned_10b),
        .valid_in(aligned_valid),
        .d_out(dec_8b),
        .k_out(dec_k),
        .valid_out(dec_valid),
        .code_err(code_err),
        .disp_err(disp_err)
    );

    // 3. Cut-Through Header ECC & Payload CRC Checker (@ clk_cdr)
    wire [7:0] checker_data;
    wire       checker_valid;
    wire       checker_last;

    ecc_crc_checker #(
        .TARGET_VC(TARGET_VC)
    ) u_checker (
        .clk(clk_cdr),
        .rst_n(rst_n),
        .d_in(dec_8b),
        .k_in(dec_k),
        .valid_in(dec_valid),
        .d_out(checker_data),
        .valid_out(checker_valid),
        .last_out(checker_last),
        .ecc_ok(ecc_ok),
        .ecc_corrected(ecc_corrected),
        .ecc_error(ecc_error),
        .crc_error(crc_error),
        .data_id(rx_data_id),
        .word_count(),
        .packet_done()
    );

    // 4. Asymmetric AXI-Stream Async FIFO Bridge (8-bit @ clk_cdr -> 24-bit @ clk_sys)
    wire        hdr_ready;     // back-pressure: parser -> FIFO
    wire        unpack_ready;  // back-pressure: unpacker -> parser
    wire [23:0] fifo_24b_data;
    wire [2:0]  fifo_24b_keep;
    wire        fifo_24b_valid;
    wire        fifo_24b_last;

    axis_asyncc_fifo #(
        .depth(4096)
    ) u_cdc_fifo (
        .s_axis_aclk(clk_cdr),
        .s_axis_aresetn(rst_n),
        .s_axis_tdata(checker_data),
        .s_axis_tvalid(checker_valid),
        .s_axis_tready(),
        .s_axis_tlast(checker_last),

        .m_axis_aclk(clk_sys),
        .m_axis_aresetn(rst_n),
        .m_axis_tdata(fifo_24b_data),
        .m_axis_tkeep(fifo_24b_keep),
        .m_axis_tvalid(fifo_24b_valid),
        .m_axis_tready(hdr_ready),
        .m_axis_tlast(fifo_24b_last)
    );

    // 5. MIPI Header Parser (@ clk_sys)
    wire [7:0]  hdr_data_id;
    wire [15:0] hdr_word_count;
    wire        hdr_valid;

    wire [23:0] unpack_data;
    wire [2:0]  unpack_keep;
    wire        unpack_valid;
    wire        unpack_last;

    mipi_hdr_parser u_hdr_parser (
        .clk(clk_sys),
        .rst_n(rst_n),
        .s_axis_tdata(fifo_24b_data),
        .s_axis_tkeep(fifo_24b_keep),
        .s_axis_tvalid(fifo_24b_valid),
        .s_axis_tready(hdr_ready),
        .s_axis_tlast(fifo_24b_last),

        .data_id(hdr_data_id),
        .word_count(hdr_word_count),
        .hdr_valid(hdr_valid),

        .m_axis_tdata(unpack_data),
        .m_axis_tkeep(unpack_keep),
        .m_axis_tvalid(unpack_valid),
        .m_axis_tready(unpack_ready),
        .m_axis_tlast(unpack_last)
    );

    // 6. 24-bit Pixel Unpacker (@ clk_sys)
    pixel_unpack u_unpack (
        .clk(clk_sys),
        .rst_n(rst_n),
        .data_type(hdr_data_id[5:0]),
        .s_axis_tdata(unpack_data),
        .s_axis_tkeep(unpack_keep),
        .s_axis_tvalid(unpack_valid),
        .s_axis_tready(unpack_ready),
        .s_axis_tlast(unpack_last),
        .px_out(px_out),
        .px_valid(px_valid),
        .px_last(px_last)
    );

endmodule
