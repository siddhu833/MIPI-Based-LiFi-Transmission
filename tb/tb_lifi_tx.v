`timescale 1ns/1ps

module tb_lifi_tx;

    reg clk_phy;
    reg rst_n;

    initial begin
        clk_phy = 0;
        forever #2.5 clk_phy = ~clk_phy; // 200 MHz
    end

    reg [7:0] phy_byte;
    reg       phy_valid;
    reg       phy_sot;
    reg       phy_eot;

    wire led_tx_serial;
    wire tx_active;

    lifi_tx_top u_tx (
        .clk_phy(clk_phy),
        .rst_n(rst_n),
        .phy_byte(phy_byte),
        .phy_valid(phy_valid),
        .phy_sot(phy_sot),
        .phy_eot(phy_eot),
        .led_tx_serial(led_tx_serial),
        .tx_active(tx_active)
    );

    initial begin
        $display("--- Standalone Transmitter (lifi_tx_top) Testbench ---");
        rst_n     = 0;
        phy_byte  = 8'h00;
        phy_valid = 0;
        phy_sot   = 0;
        phy_eot   = 0;

        #20;
        rst_n = 1;
        #20;

        // Send a 4-byte MIPI Header (RAW10: DataID 0x2B, WordCount = 5)
        @(posedge clk_phy);
        phy_sot   <= 1;
        phy_valid <= 1;
        phy_byte  <= 8'h2B; // Header 0: RAW10

        @(posedge clk_phy);
        phy_sot   <= 0;
        phy_byte  <= 8'h05; // Header 1: WC LSB = 5

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // Header 2: WC MSB = 0

        @(posedge clk_phy);
        phy_byte  <= 8'h00; // Header 3: ECC

        // Send 5 payload bytes
        @(posedge clk_phy); phy_byte <= 8'hAA;
        @(posedge clk_phy); phy_byte <= 8'hBB;
        @(posedge clk_phy); phy_byte <= 8'hCC;
        @(posedge clk_phy); phy_byte <= 8'hDD;
        @(posedge clk_phy); phy_byte <= 8'h11; // LSBs

        // Send CRC
        @(posedge clk_phy); phy_byte <= 8'h00;
        @(posedge clk_phy); phy_byte <= 8'h00;

        @(posedge clk_phy);
        phy_eot   <= 1;
        phy_valid <= 0;

        @(posedge clk_phy);
        phy_eot   <= 0;

        #200;
        $display("TX Test Complete.");
        $finish;
    end

    always @(posedge clk_phy) begin
        if (tx_active) begin
            $display("[TX Serial Out] bit = %b", led_tx_serial);
        end
    end

endmodule
