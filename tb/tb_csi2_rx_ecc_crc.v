`timescale 1ns/1ps

module tb_csi2_rx_ecc_crc;

    // Clocks and Resets
    reg clk_phy;  // 200 MHz D-PHY / TX clock
    reg clk_sys;  // 100 MHz System clock (RX side)
    reg rst_n;

    initial begin
        clk_phy = 0;
        forever #2.5 clk_phy = ~clk_phy; // 200 MHz (5 ns period)
    end

    initial begin
        clk_sys = 0;
        forever #5.0 clk_sys = ~clk_sys; // 100 MHz (10 ns period)
    end

    // D-PHY Stimulus
    reg [7:0] phy_byte;
    reg       phy_valid;
    reg       phy_sot;
    reg       phy_eot;

    // -------------------------------------------------------------------------
    // TX Side Chain
    // -------------------------------------------------------------------------
    wire [7:0] tx_llp_data;
    wire       tx_llp_valid;
    wire       tx_llp_last;
    wire       tx_crc_err;

    csi2_rx_llp_sf #(
        .TARGET_VC(2'b00)
    ) tx_llp (
        .clk(clk_phy),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .m_axis_tdata(tx_llp_data),
        .m_axis_tvalid(tx_llp_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(tx_llp_last),
        .crc_error(tx_crc_err)
    );

    wire [7:0] framer_data;
    wire       framer_k;
    wire       framer_valid;

    lifi_framer tx_framer (
        .clk(clk_phy),
        .rst_n(rst_n),
        .phy_byte(tx_llp_data),
        .phy_valid(tx_llp_valid),
        .phy_sot(phy_sot),
        .phy_eot(phy_eot),
        .data_out(framer_data),
        .k_out(framer_k),
        .valid_out(framer_valid)
    );

    wire [9:0] encoded_10b;
    wire       encoded_valid;

    encoder_8b10b tx_encoder (
        .clk(clk_phy),
        .rst_n(rst_n),
        .d_in(framer_data),
        .k_in(framer_k),
        .valid_in(framer_valid),
        .q_out(encoded_10b),
        .valid_out(encoded_valid)
    );

    // -------------------------------------------------------------------------
    // Optical Link (Simulated Channel)
    // -------------------------------------------------------------------------
    wire [9:0] rx_channel_10b = encoded_10b;
    wire       rx_channel_valid = encoded_valid;

    // -------------------------------------------------------------------------
    // RX Side Chain
    // -------------------------------------------------------------------------
    wire [9:0] aligned_10b;
    wire       aligned_valid;
    wire       aligned_lock;

    lifi_rx_aligner rx_aligner (
        .clk(clk_phy),
        .rst_n(rst_n),
        .raw_10b_in(rx_channel_10b),
        .valid_in(rx_channel_valid),
        .aligned_10b_out(aligned_10b),
        .aligned_valid(aligned_valid),
        .aligned_lock(aligned_lock)
    );

    wire [7:0] decoded_8b;
    wire       decoded_k;
    wire       decoded_valid;
    wire       code_err, disp_err;

    decoder_8b10b rx_decoder (
        .clk(clk_phy),
        .rst_n(rst_n),
        .d_in(aligned_10b),
        .valid_in(aligned_valid),
        .d_out(decoded_8b),
        .k_out(decoded_k),
        .valid_out(decoded_valid),
        .code_err(code_err),
        .disp_err(disp_err)
    );

    wire [7:0] rx_checker_data;
    wire       rx_checker_valid;
    wire       rx_checker_last;
    wire       rx_crc_err;

    ecc_crc_checker rx_ecc_crc (
        .clk(clk_phy),
        .rst_n(rst_n),
        .d_in(decoded_8b),
        .k_in(decoded_k),
        .valid_in(decoded_valid),
        .d_out(rx_checker_data),
        .valid_out(rx_checker_valid),
        .last_out(rx_checker_last),
        .crc_error(rx_crc_err)
    );

    // Asymmetric FIFO Bridge (8-bit @ clk_phy -> 24-bit @ clk_sys)
    wire [23:0] fifo_24b_data;
    wire [2:0]  fifo_24b_keep;
    wire        fifo_24b_valid;
    wire        fifo_24b_last;

    axis_asyncc_fifo #(
        .depth(256)
    ) cdc_fifo (
        .s_axis_aclk(clk_phy),
        .s_axis_aresetn(rst_n),
        .s_axis_tdata(rx_checker_data),
        .s_axis_tvalid(rx_checker_valid),
        .s_axis_tready(),
        .s_axis_tlast(rx_checker_last),

        .m_axis_aclk(clk_sys),
        .m_axis_aresetn(rst_n),
        .m_axis_tdata(fifo_24b_data),
        .m_axis_tkeep(fifo_24b_keep),
        .m_axis_tvalid(fifo_24b_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(fifo_24b_last)
    );

    wire [7:0]  hdr_data_id;
    wire [15:0] hdr_word_count;
    wire        hdr_valid;

    wire [23:0] unpack_in_data;
    wire [2:0]  unpack_in_keep;
    wire        unpack_in_valid;
    wire        unpack_in_last;

    mipi_hdr_parser hdr_parser (
        .clk(clk_sys),
        .rst_n(rst_n),
        .s_axis_tdata(fifo_24b_data),
        .s_axis_tkeep(fifo_24b_keep),
        .s_axis_tvalid(fifo_24b_valid),
        .s_axis_tready(),
        .s_axis_tlast(fifo_24b_last),

        .data_id(hdr_data_id),
        .word_count(hdr_word_count),
        .hdr_valid(hdr_valid),

        .m_axis_tdata(unpack_in_data),
        .m_axis_tkeep(unpack_in_keep),
        .m_axis_tvalid(unpack_in_valid),
        .m_axis_tready(1'b1),
        .m_axis_tlast(unpack_in_last)
    );

    wire [23:0] pixel_rgb;
    wire        pixel_valid;
    wire        pixel_last;

    pixel_unpack unpacker (
        .clk(clk_sys),
        .rst_n(rst_n),
        .data_type(hdr_data_id[5:0]),
        .s_axis_tdata(unpack_in_data),
        .s_axis_tkeep(unpack_in_keep),
        .s_axis_tvalid(unpack_in_valid),
        .s_axis_tready(),
        .s_axis_tlast(unpack_in_last),
        .px_out(pixel_rgb),
        .px_valid(pixel_valid),
        .px_last(pixel_last)
    );

    // -------------------------------------------------------------------------
    // Test Procedure
    // -------------------------------------------------------------------------
    integer i;

    initial begin
        $display("==================================================================");
        $display("   Starting End-to-End Li-Fi MIPI CSI-2 Full Chain Simulation     ");
        $display("==================================================================");

        rst_n     = 0;
        phy_byte  = 8'h00;
        phy_valid = 0;
        phy_sot   = 0;
        phy_eot   = 0;

        #20;
        rst_n = 1;
        #20;

        // Send MIPI CSI-2 Packet (RGB888 Data Type 0x24, VC 0, Word Count = 6 bytes -> 2 pixels)
        // Header: [DataID=0x24, WC_LSB=0x06, WC_MSB=0x00, ECC=0x00]
        $display("[TB] Sending Packet: RGB888 (6 bytes payload)...");

        @(posedge clk_phy);
        phy_sot   <= 1;
        phy_valid <= 1;
        phy_byte  <= 8'h24; // Header 0: Data ID (RGB888)

        @(posedge clk_phy);
        phy_sot   <= 0;
        phy_byte  <= 8'h06; // Header 1: WC LSB (6 bytes)

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // Header 2: WC MSB

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // Header 3: ECC

        // Payload: 6 Bytes (Pixel 1: R=0xFF, G=0x00, B=0x00; Pixel 2: R=0x00, G=0xFF, B=0x00)
        @(posedge clk_phy); phy_byte <= 8'hFF;
        @(posedge clk_phy); phy_byte <= 8'h00;
        @(posedge clk_phy); phy_byte <= 8'h00;
        @(posedge clk_phy); phy_byte <= 8'h00;
        @(posedge clk_phy); phy_byte <= 8'hFF;
        @(posedge clk_phy); phy_byte <= 8'h00;

        // CRC bytes (dummy)
        @(posedge clk_phy); phy_byte <= 8'h12;
        @(posedge clk_phy); phy_byte <= 8'h34;

        @(posedge clk_phy);
        phy_eot   <= 1;
        phy_valid <= 0;

        @(posedge clk_phy);
        phy_eot   <= 0;

        #500;
        $display("[TB] End of Simulation.");
        $finish;
    end

    always @(posedge clk_sys) begin
        if (pixel_valid) begin
            $display("[TB] RX Output Pixel RGB24: 0x%06X (last=%b)", pixel_rgb, pixel_last);
        end
    end

endmodule
