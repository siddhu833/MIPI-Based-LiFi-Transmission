`timescale 1ns / 1ps

module tb_lifi_tx_top();

    // ==========================================
    // Signals
    // ==========================================
    reg         clk_mipi;
    reg         clk_tx;
    reg         aresetn;
    
    reg  [7:0]  s_axis_tdata;
    reg         s_axis_tvalid;
    reg         s_axis_tlast;
    reg         tx_enable;
    
    wire        s_axis_tready;
    wire        tx_fifo_full;
    wire        led_data_out;

    // ==========================================
    // Instantiate the Unit Under Test (UUT)
    // ==========================================
    lifi_tx_top uut (
        .clk_sys        (clk_mipi),
        .clk_tx         (clk_tx),
        .aresetn        (aresetn),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .tx_enable      (tx_enable),
        .tx_fifo_full   (tx_fifo_full),
        .led_data_out   (led_data_out)
    );

    // ==========================================
    // Clock Generation
    // ==========================================
    // clk_sys: 100 MHz (10ns period)
    initial begin
        clk_mipi = 0;
        forever #5 clk_mipi = ~clk_mipi;
    end

    // clk_tx: 50 MHz (20ns period)
    initial begin
        clk_tx = 0;
        forever #10 clk_tx = ~clk_tx;
    end

       // ==========================================
    // AXI-Stream Send Task
    // ==========================================
    task send_byte;
        input [7:0] data;
        input       is_last;
        begin
            // Wait for the next clock edge to drive data
            @(posedge clk_mipi);
            s_axis_tdata  <= data;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= is_last;
            
            // Wait for the handshake (tready must be high)
            // This replaces the 'disable wait_loop' logic
            @(posedge clk_mipi);
            while (!s_axis_tready) begin
                @(posedge clk_mipi);
            end
            
            // Deassert valid after handshake
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask
    // ==========================================
    // Main Stimulus
    // ==========================================
    initial begin
        // Initialize Inputs
        aresetn       = 0;
        s_axis_tdata  = 0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;
        tx_enable     = 0;

        // Hold reset for 50ns
        #50;
        aresetn = 1;
        tx_enable = 1;
        
        // Wait a bit to see IDLE characters being sent
        #100;

        // ==========================================
        // Send Packet 1 (4 bytes)
        // ==========================================
        $display("[%0t] Sending Packet 1...", $time);
        send_byte(8'hAA, 1'b0); // Byte 1 (Header)
        send_byte(8'hBB, 1'b0); // Byte 2 (Header)
        send_byte(8'hCC, 1'b0); // Byte 3 (Payload)
        send_byte(8'hDD, 1'b1); // Byte 4 (Payload + TLAST)

        // Simulate MIPI Blanking (No data being sent)
        // During this time, the Framer should be sending IDLE characters (K.28.5)
        #200;

        // ==========================================
        // Send Packet 2 (2 bytes)
        // ==========================================
        $display("[%0t] Sending Packet 2...", $time);
        send_byte(8'h12, 1'b0); // Byte 1
        send_byte(8'h34, 1'b1); // Byte 2 + TLAST

        // Let the simulator run to shift out the last bits
        #500;

        $display("[%0t] Simulation Finished.", $time);
        $finish;
    end

    // ==========================================
    // Optional: Monitor the LED output
    // ==========================================
    initial begin
        $dumpfile("lifi_tx_waveform.vcd");
        $dumpvars(0, tb_lifi_tx_top);
    end

endmodule