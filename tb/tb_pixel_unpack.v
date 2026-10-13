`timescale 1ns / 1ps

// Standalone unit test for pixel_unpack with its new 24-bit input +
// s_axis_tkeep interface (companion to the full-chain tb_csi2_rx_ecc_crc.v).
module tb_pixel_unpack();

    reg         clk;
    reg         rst_n;
    reg  [5:0]  data_type;
    reg  [23:0] s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    reg  [2:0]  s_axis_tkeep;

    wire        s_axis_tready;
    wire [23:0] px_out;
    wire        px_valid;
    wire        px_last;

    integer     errors;

    pixel_unpack #(
        .AXIS_WIDTH(24),
        .pixal_widht(24)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_type(data_type),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tkeep(s_axis_tkeep),
        .px_out(px_out),
        .px_valid(px_valid),
        .px_last(px_last)
    );

    always #5 clk = ~clk; // 100 MHz

    // Sends one 24-bit beat carrying `nbytes` valid bytes (1-3, packed
    // LSB-first: byte0 in bits [7:0], byte1 in [15:8], byte2 in [23:16]).
    task send_beat(input [23:0] data, input [1:0] nbytes, input is_last);
        begin
            wait (s_axis_tready == 1'b1);
            s_axis_tdata  = data;
            s_axis_tkeep  = (nbytes == 2'd1) ? 3'b001 :
                             (nbytes == 2'd2) ? 3'b011 : 3'b111;
            s_axis_tvalid = 1;
            s_axis_tlast  = is_last;
            @(posedge clk);
            #1;
            s_axis_tvalid = 0;
            s_axis_tlast  = 0;
        end
    endtask

    task check_pixel(input [23:0] expected, input [255:0] label);
        begin
            @(posedge clk);
            #1;
            while (!px_valid) begin
                @(posedge clk);
                #1;
            end
            if (px_out !== expected) begin
                $display("  [FAIL] %0s: got %h, expected %h", label, px_out, expected);
                errors = errors + 1;
            end else begin
                $display("  [PASS] %0s = %h (last=%b)", label, px_out, px_last);
            end
        end
    endtask

    initial begin
        clk           = 0;
        rst_n         = 0;
        data_type     = 6'h00;
        s_axis_tdata  = 0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        s_axis_tkeep  = 0;
        errors        = 0;

        $display("=================================================");
        $display("   Pixel Unpacker Unit Testbench (24-bit input)");
        $display("=================================================");

        #20;
        rst_n = 1;
        #20;

        // ---------------------------------------------------------
        // TEST 1: RAW8 — 3 valid bytes in one beat -> 3 pixels
        // ---------------------------------------------------------
        $display("\n--- TEST 1: RAW8 Format (3 bytes/beat) ---");
        data_type = 6'h2A;
        send_beat({8'hCC, 8'hBB, 8'hAA}, 2'd3, 1'b1);
        check_pixel(24'h0000AA, "RAW8 px0");
        check_pixel(24'h0000BB, "RAW8 px1");
        check_pixel(24'h0000CC, "RAW8 px2");

        #20;

        // ---------------------------------------------------------
        // TEST 2: RGB888 — 3 bytes -> 1 pixel, perfectly aligned
        // ---------------------------------------------------------
        $display("\n--- TEST 2: RGB888 Format ---");
        data_type = 6'h24;
        send_beat({8'hCC, 8'hBB, 8'hAA}, 2'd3, 1'b1); // R=AA G=BB B=CC
        check_pixel(24'hCCBBAA, "RGB888 px0");

        #20;

        // ---------------------------------------------------------
        // TEST 3: RAW10 — 5 bytes across two beats -> 4 pixels
        // ---------------------------------------------------------
        $display("\n--- TEST 3: RAW10 Format (5 bytes over 2 beats) ---");
        data_type = 6'h2B;
        // Beat 1: 3 MSB bytes (px0,px1,px2 MSBs)
        send_beat({8'h33, 8'h22, 8'h11}, 2'd3, 1'b0);
        // Beat 2: px3 MSB + LSB byte (2 bytes, last)
        send_beat({8'h00, 8'hE4, 8'h44}, 2'd2, 1'b1);
        check_pixel(24'h000044, "RAW10 px0"); // {0x11,00}
        check_pixel(24'h000089, "RAW10 px1"); // {0x22,01}
        check_pixel(24'h0000CE, "RAW10 px2"); // {0x33,10}
        check_pixel(24'h000113, "RAW10 px3"); // {0x44,11}

        #20;

        // ---------------------------------------------------------
        // TEST 4: RAW12 — 3 bytes -> 2 pixels, perfectly aligned
        // ---------------------------------------------------------
        $display("\n--- TEST 4: RAW12 Format ---");
        data_type = 6'h2C;
        send_beat({8'hA5, 8'hEE, 8'hDD}, 2'd3, 1'b1);
        check_pixel(24'h000DD5, "RAW12 px0");
        check_pixel(24'h000EEA, "RAW12 px1");

        #20;

        $display("\n=================================================");
        if (errors == 0)
            $display("   ALL TESTS PASSED");
        else
            $display("   %0d TEST(S) FAILED", errors);
        $display("=================================================\n");
        $finish;
    end

endmodule
