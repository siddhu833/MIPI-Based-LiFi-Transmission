`timescale 1ns/1ps

module tb_lifi_system;

    reg clk_bit; // 2.0 GHz 10x bit clock
    reg clk_phy; // 200 MHz symbol clock
    reg clk_sys; // 100 MHz system clock
    reg rst_n;

    initial begin
        clk_bit = 0;
        forever #0.25 clk_bit = ~clk_bit; // 2.0 GHz (0.5 ns period)
    end

    initial begin
        clk_phy = 0;
        forever #2.5 clk_phy = ~clk_phy; // 200 MHz (5.0 ns period)
    end

    initial begin
        clk_sys = 0;
        forever #5.0 clk_sys = ~clk_sys; // 100 MHz (10.0 ns period)
    end

    reg [7:0] phy_byte;
    reg       phy_valid;
    reg       phy_sot;
    reg       phy_eot;

    wire [23:0] px_out;
    wire        px_valid;
    wire        px_last;
    wire        tx_active;
    wire        rx_lock;
    wire        ecc_ok, ecc_corrected, ecc_error, crc_error;
    wire [7:0]  rx_data_id;

    lifi_system_top u_system (
        .clk_phy(clk_phy),
        .clk_bit(clk_bit),
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .phy_sot(phy_sot),
        .phy_eot(phy_eot),
        .px_out(px_out),
        .px_valid(px_valid),
        .px_last(px_last),
        .tx_active(tx_active),
        .rx_lock(rx_lock),
        .ecc_ok(ecc_ok),
        .ecc_corrected(ecc_corrected),
        .ecc_error(ecc_error),
        .crc_error(crc_error),
        .rx_data_id(rx_data_id)
    );

    initial begin
        $display("==================================================================");
        $display("   Master Li-Fi 1-BIT Serial MIPI CSI-2 System Simulation         ");
        $display("==================================================================");

        rst_n     = 0;
        phy_byte  = 8'h00;
        phy_valid = 0;
        phy_sot   = 0;
        phy_eot   = 0;

        #50;
        rst_n = 1;
        #50;

        // TEST 1: Raspberry Pi Camera RAW10 Packet (Data Type 0x2B, 5 bytes payload -> 4 pixels)
        $display("\n[TB] Sending Test Packet: Raspberry Pi Camera RAW10 (0x2B)...");
        
        @(posedge clk_phy);
        phy_sot   <= 1;
        phy_valid <= 1;
        phy_byte  <= 8'h2B; // RAW10 Data ID

        @(posedge clk_phy);
        phy_sot   <= 0;
        phy_byte  <= 8'h05; // WC LSB = 5 bytes

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // WC MSB = 0

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // ECC

        // 5 RAW10 Payload Bytes:
        @(posedge clk_phy); phy_byte <= 8'hC0;
        @(posedge clk_phy); phy_byte <= 8'hB0;
        @(posedge clk_phy); phy_byte <= 8'hA0;
        @(posedge clk_phy); phy_byte <= 8'h90;
        @(posedge clk_phy); phy_byte <= 8'h1B;

        // CRC
        @(posedge clk_phy); phy_byte <= 8'h00;
        @(posedge clk_phy); phy_byte <= 8'h00;

        @(posedge clk_phy);
        phy_eot   <= 1;
        phy_valid <= 0;

        @(posedge clk_phy);
        phy_eot   <= 0;

        #2000;
        $display("\n==================================================================");
        $display("   1-Bit Serial System Simulation Completed Successfully!         ");
        $display("==================================================================");
        $finish;
    end

    always @(posedge clk_sys) begin
        if (px_valid) begin
            $display("[RX Output Pixel @ clk_sys] RGB24 = 0x%06X (last=%b)", px_out, px_last);
        end
    end

endmodule
