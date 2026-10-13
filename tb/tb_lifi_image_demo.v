`timescale 1ns/1ps

module tb_lifi_image_demo;

    reg clk_bit; // 2.0 GHz 10x bit clock
    reg clk_phy; // 200 MHz symbol clock
    reg clk_sys; // 100 MHz system clock
    reg rst_n;

    initial begin
        clk_bit = 0;
        forever #0.25 clk_bit = ~clk_bit; // 2.0 GHz
    end

    initial begin
        clk_phy = 0;
        forever #2.5 clk_phy = ~clk_phy; // 200 MHz
    end

    initial begin
        clk_sys = 0;
        forever #5.0 clk_sys = ~clk_sys; // 100 MHz
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

    integer file_in, file_out;
    reg [8*10-1:0] token;
    reg [7:0] hex_val;
    integer status;

    initial begin
        $display("==================================================================");
        $display("   Image Transmission Demo: Python -> Verilog FPGA -> Python      ");
        $display("==================================================================");

        file_out = $fopen("tb/mipi_rx_pixels.hex", "w");
        file_in  = $fopen("tb/mipi_tx_stream.hex", "r");

        if (file_in == 0) begin
            $display("[Error] Could not open tb/mipi_tx_stream.hex!");
            $finish;
        end

        rst_n     = 0;
        phy_byte  = 8'h00;
        phy_valid = 0;
        phy_sot   = 0;
        phy_eot   = 0;

        #50;
        rst_n = 1;
        #50;

        while (!$feof(file_in)) begin
            status = $fscanf(file_in, "%s\n", token);
            if (status == 1) begin
                if (token == "SOT") begin
                    @(posedge clk_phy);
                    phy_sot   <= 1;
                    phy_valid <= 0;
                    @(posedge clk_phy);
                    phy_sot   <= 0;
                    repeat (4) @(posedge clk_phy); // Wait for Preamble & Comma framing
                end else if (token == "EOT") begin
                    @(posedge clk_phy);
                    phy_eot   <= 1;
                    phy_valid <= 0;
                    @(posedge clk_phy);
                    phy_eot   <= 0;
                    #100;
                end else begin
                    status = $sscanf(token, "%x", hex_val);
                    @(posedge clk_phy);
                    phy_byte  <= hex_val;
                    phy_valid <= 1;
                end
            end
        end

        $fclose(file_in);

        #30000;
        $fclose(file_out);
        $display("[Verilog] 1-Bit Serial Image Simulation completed.");
        $display("[Verilog] pixels received = %0d, ecc_error cycles = %0d, crc_error cycles = %0d",
                 px_count, ecc_err_cnt, crc_err_cnt);
        $finish;
    end

    // Error / count monitors (CRC and ECC must be clean for a good transfer)
    integer px_count = 0, ecc_err_cnt = 0, crc_err_cnt = 0, ecc_corr_cnt = 0;
    always @(posedge clk_phy) begin
        if (ecc_error)     ecc_err_cnt  = ecc_err_cnt + 1;
        if (crc_error)     crc_err_cnt  = crc_err_cnt + 1;
        if (ecc_corrected) ecc_corr_cnt = ecc_corr_cnt + 1;
    end

    always @(posedge clk_sys) begin
        if (px_valid) begin
            px_count = px_count + 1;
            $fwrite(file_out, "%06X\n", px_out);
        end
    end

endmodule
