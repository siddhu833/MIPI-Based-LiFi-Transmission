`timescale 1ns/1ps
// =============================================================================
// pixel_unpack.v
// RX-side Pixel Unpacker (24-bit AXI-Stream Input, with back-pressure)
//
// Optimized for Raspberry Pi Camera MIPI CSI-2 RAW10 (Data Type 0x2B)
// Also supports RGB888 (0x24) and RAW8 (0x2A).
//
// MIPI CSI-2 RAW10 Packing (5 bytes -> 4 x 10-bit pixels):
//   Byte 0: Pixel 0 [9:2]   Byte 1: Pixel 1 [9:2]
//   Byte 2: Pixel 2 [9:2]   Byte 3: Pixel 3 [9:2]
//   Byte 4: {Pixel 3[1:0], Pixel 2[1:0], Pixel 1[1:0], Pixel 0[1:0]}
//
// RAW10 path: each 24-bit word is consumed one byte per clock (tkeep marks the
// valid bytes of the last word). Every 5th byte completes a group, which is
// copied to an output register and emitted as 4 pixels (1 per clock) while the
// next group is collected. Pixel value = top 8 bits replicated to RGB24.
// s_axis_tready is low only while a word is being consumed.
// =============================================================================
module pixel_unpack (
    input  wire        clk,
    input  wire        rst_n,

    // MIPI Data Type from Header Parser (lower 6 bits of data_id)
    input  wire [5:0]  data_type,

    // 24-bit AXI-Stream input (3 bytes / word)
    input  wire [23:0] s_axis_tdata,
    input  wire [2:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // Pixel output (RGB24 / Grayscale 24-bit)
    output reg  [23:0] px_out,
    output reg         px_valid,
    output reg         px_last
);

    localparam DT_RGB888 = 6'h24;
    localparam DT_RAW8   = 6'h2A;
    localparam DT_RAW10  = 6'h2B;

    wire is_raw10 = (data_type == DT_RAW10);

    // ---- word latch (RAW10 path) --------------------------------------------
    reg [23:0] w_data;
    reg [2:0]  w_keep;
    reg        w_last;
    reg        w_valid;
    reg [1:0]  w_idx;            // next byte of the latched word

    // ---- group collection ---------------------------------------------------
    reg [7:0]  grp [0:4];
    reg [2:0]  g_cnt;

    // ---- pixel emission -----------------------------------------------------
    reg [7:0]  og [0:4];
    reg [2:0]  e_idx;            // 0..3 pixel being emitted
    reg        e_busy;
    reg        e_last;

    wire [7:0] cur_byte  = (w_idx == 2'd0) ? w_data[7:0] :
                           (w_idx == 2'd1) ? w_data[15:8] : w_data[23:16];
    // this byte is the final valid byte of the latched word
    wire       last_byte = (w_idx == 2'd2) || !w_keep[w_idx + 1'b1];
    wire       completes = (g_cnt == 3'd4);
    // a completed group needs a free output register (free when not emitting,
    // or when emitting its final pixel this very cycle)
    wire       out_free  = !e_busy || (e_idx == 3'd3);
    wire       consume   = w_valid && (!completes || out_free);

    assign s_axis_tready = is_raw10 ? (!w_valid || (consume && last_byte)) : 1'b1;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px_out  <= 24'd0;
            px_valid<= 1'b0;
            px_last <= 1'b0;
            w_data  <= 24'd0;
            w_keep  <= 3'd0;
            w_last  <= 1'b0;
            w_valid <= 1'b0;
            w_idx   <= 2'd0;
            g_cnt   <= 3'd0;
            e_idx   <= 3'd0;
            e_busy  <= 1'b0;
            e_last  <= 1'b0;
            for (k = 0; k < 5; k = k + 1) begin grp[k] <= 8'd0; og[k] <= 8'd0; end
        end else begin
            px_valid <= 1'b0;
            px_last  <= 1'b0;

            if (!is_raw10) begin
                w_valid <= 1'b0;
                g_cnt   <= 3'd0;
                e_busy  <= 1'b0;
                if (s_axis_tvalid) begin
                    px_valid <= 1'b1;
                    px_last  <= s_axis_tlast;
                    case (data_type)
                        DT_RAW8: px_out <= {s_axis_tdata[7:0], s_axis_tdata[7:0], s_axis_tdata[7:0]};
                        default: px_out <= s_axis_tdata;   // RGB888 and unknown types
                    endcase
                end
            end else begin
                // ---- emit current group, 1 pixel per clock ----
                if (e_busy) begin
                    px_out   <= {og[e_idx[1:0]], og[e_idx[1:0]], og[e_idx[1:0]]};
                    px_valid <= 1'b1;
                    if (e_idx == 3'd3) begin
                        px_last <= e_last;
                        e_busy  <= 1'b0;
                    end
                    e_idx <= e_idx + 1'b1;
                end

                // ---- consume one byte of the latched word ----
                if (consume) begin
                    if (completes) begin
                        // 5th byte of the group: copy to output regs, start emitting
                        og[0] <= grp[0]; og[1] <= grp[1]; og[2] <= grp[2]; og[3] <= grp[3];
                        og[4] <= cur_byte;
                        e_busy <= 1'b1;
                        e_idx  <= 3'd0;
                        e_last <= w_last && last_byte;
                        g_cnt  <= 3'd0;
                    end else begin
                        grp[g_cnt] <= cur_byte;
                        g_cnt      <= g_cnt + 1'b1;
                    end
                    if (last_byte) begin
                        w_valid <= 1'b0;
                        w_idx   <= 2'd0;
                        if (w_last) g_cnt <= 3'd0;   // new line starts on a group boundary
                    end else begin
                        w_idx <= w_idx + 1'b1;
                    end
                end

                // ---- latch a new word when free (or being freed this cycle) ----
                if (s_axis_tvalid && s_axis_tready) begin
                    w_data  <= s_axis_tdata;
                    w_keep  <= s_axis_tkeep;
                    w_last  <= s_axis_tlast;
                    w_valid <= 1'b1;
                    w_idx   <= 2'd0;
                end
            end
        end
    end

endmodule
