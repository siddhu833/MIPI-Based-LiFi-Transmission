`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: siddardhareddy duggu
// Module Name: lifi_tx_top
// Project Name: lifi tx
// Description: Top-level Li-Fi Transmitter. Bridges MIPI camera clock to high-speed 
//              LED clock, frames the packet, encodes it, and serializes it to the LED.
//////////////////////////////////////////////////////////////////////////////////

module lifi_tx_top (
    // ==========================================
    // 1. Clocks & Reset
    // ==========================================
    input wire          clk_mipi,        // MIPI Parallel data clock (from camera D-PHY)
    input wire          clk_tx,         // High-speed serial LED clock (from FPGA PLL)
    input wire          aresetn,        // Active-low asynchronous reset

    // ==========================================
    // 2. AXI-Stream Input (Raw MIPI LLP Bytes)
    // ==========================================
    input wire [7:0]    s_axis_tdata,   // 8-bit raw MIPI byte
    input wire          s_axis_tvalid,  // Data is valid
    output wire         s_axis_tready,  // TX is ready to receive data
    input wire          s_axis_tlast,   // Marks end of MIPI LLP packet

    // ==========================================
    // 3. Control / Status
    // ==========================================
    input wire          tx_enable,      // From PS/AXI register (Turns TX on/off)
    output wire         tx_fifo_full,   // Status flag for the processor/camera

    // ==========================================
    // 4. Physical LED Output
    // ==========================================
    output wire         led_data_out    // 1-bit high-speed serial stream to the LED
);

    // =========================================================================
    // Internal Wires (Connecting the 4 blocks)
    // =========================================================================
    wire        fifo_full_int;
    wire        fifo_empty_int;
    wire        fifo_rd_en_int;
    wire [7:0]  fifo_dout_int;
    wire        fifo_last_int;
    
    wire [7:0]  enc_data_w;
    wire        enc_is_k_w;
    wire [9:0]  enc_10b_w;
    wire        tx_ready_w;

    // =========================================================================
    // 1. ASYNC FIFO (Clock Domain Crossing: clk_sys -> clk_tx)
    // =========================================================================
    // Pack {s_axis_tlast, s_axis_tdata} into 9 bits so TLAST crosses clock domains
    wire [8:0] fifo_din_w  = {s_axis_tlast, s_axis_tdata};
    wire [8:0] fifo_dout_w;
    wire       fifo_w_en   = s_axis_tvalid && s_axis_tready && tx_enable;

    assign s_axis_tready = !fifo_full_int && tx_enable;
    assign tx_fifo_full  = fifo_full_int;
    assign fifo_last_int = fifo_dout_w[8];
    assign fifo_dout_int = fifo_dout_w[7:0];

    asyncc_fifo #(
        .depth(16),
        .width(9)
    ) u_async_fifo (
        .clk_w    (clk_mipi),
        .clk_r    (clk_tx),
        .rst_w    (!aresetn),
        .rst_r    (!aresetn),
        .w_en     (fifo_w_en),
        .r_en     (fifo_rd_en_int),
        .data_in  (fifo_din_w),
        .full     (fifo_full_int),
        .empty    (fifo_empty_int),
        .data_out (fifo_dout_w)
    );

    // =========================================================================
    // 2. Li-Fi Framer
    // =========================================================================
    lifi_framer u_framer (
        .clk        (clk_tx),
        .rst        (aresetn),
        .fifo_dout  (fifo_dout_int),
        .fifo_empty (fifo_empty_int),
        .fifo_last  (fifo_last_int),
        .tx_ready   (tx_ready_w),   // From PISO
        .fifo_rd_en (fifo_rd_en_int),
        .enc_data   (enc_data_w),   // To Encoder
        .enc_is_k   (enc_is_k_w)    // To Encoder
    );

    // =========================================================================
// 2. 8b/10b Encoder (From GitHub - mcjtag)
// =========================================================================
encoder_8b10 u_encoder (
    .clk        (clk_tx),
    .rst        (!aresetn),      // INVERTED: GitHub code uses active-high reset
    .en         (tx_ready_w),    // CRITICAL: Only encode when PISO is ready for a new word!
    .kin        (enc_is_k_w),    // From Framer (is_k flag)
    .din        (enc_data_w),    // From Framer (8-bit data)
    .dout       (enc_10b_w),     // To PISO (10-bit encoded data)
    .disp       (),              // Leave unconnected (internal tracking)
    .kin_err    ()               // Leave unconnected (TX never errors)
);

    // =========================================================================
    // 4. PISO Serializer
    // =========================================================================
    piso_serializer u_piso (
        .clk          (clk_tx),
        .rst          (aresetn),
        .data_in      (enc_10b_w),  // From Encoder
        .tx_ready     (tx_ready_w), // To Framer
        .led_data_out (led_data_out)// To the physical FPGA pin!
    );

endmodule