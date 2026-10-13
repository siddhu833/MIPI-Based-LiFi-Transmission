`timescale 1ns/1ps
// =============================================================================
// pixel_unpack.v
// RX-side Pixel Unpacker (24-bit AXI-Stream Input)
//
// Optimized for Raspberry Pi Camera MIPI CSI-2 RAW10 (Data Type 0x2B)
// Also supports RGB888 (0x24) and RAW8 (0x2A).
//
// MIPI CSI-2 RAW10 Packing (5 bytes -> 4 x 10-bit pixels):
//   Byte 0: Pixel 0 [9:2]
//   Byte 1: Pixel 1 [9:2]
//   Byte 2: Pixel 2 [9:2]
//   Byte 3: Pixel 3 [9:2]
//   Byte 4: {Pixel 3[1:0], Pixel 2[1:0], Pixel 1[1:0], Pixel 0[1:0]}
// =============================================================================
module pixel_unpack (
    input  wire        clk,
    input  wire        rst_n,

    // MIPI Data Type from Header Parser (lower 6 bits of data_id)
    input  wire [5:0]  data_type,

    // 24-bit AXI-Stream input (3 bytes / clock)
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

    assign s_axis_tready = 1'b1;

    // Supported Data Type Codes
    localparam DT_RGB888 = 6'h24;
    localparam DT_RAW8   = 6'h2A;
    localparam DT_RAW10  = 6'h2B;
    localparam DT_RAW12  = 6'h2C;

    // Internal 5-byte buffer for RAW10 alignment across 24-bit (3-byte) boundaries
    reg [39:0] byte_buf;
    reg [2:0]  byte_count;
    reg        last_pending;

    // 10-bit reconstructed pixels
    wire [9:0] raw10_p0 = {byte_buf[7:0]  , byte_buf[33:32]};
    wire [9:0] raw10_p1 = {byte_buf[15:8] , byte_buf[35:34]};
    wire [9:0] raw10_p2 = {byte_buf[23:16], byte_buf[37:36]};
    wire [9:0] raw10_p3 = {byte_buf[31:24], byte_buf[39:38]};

    // Output multi-pixel state for RAW10
    reg [1:0] raw10_out_idx;
    reg       raw10_emitting;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            px_out         <= 24'd0;
            px_valid       <= 1'b0;
            px_last        <= 1'b0;
            byte_buf       <= 40'd0;
            byte_count     <= 3'd0;
            last_pending   <= 1'b0;
            raw10_out_idx  <= 2'd0;
            raw10_emitting <= 1'b0;
        end else begin
            px_valid <= 1'b0;
            px_last  <= 1'b0;

            if (data_type == DT_RAW10) begin
                // RAW10 Unpacking FSM
                if (raw10_emitting) begin
                    case (raw10_out_idx)
                        2'd1: begin
                            px_out         <= {raw10_p1[9:2], raw10_p1[9:2], raw10_p1[9:2]};
                            px_valid       <= 1'b1;
                            raw10_out_idx  <= 2'd2;
                        end
                        2'd2: begin
                            px_out         <= {raw10_p2[9:2], raw10_p2[9:2], raw10_p2[9:2]};
                            px_valid       <= 1'b1;
                            raw10_out_idx  <= 2'd3;
                        end
                        2'd3: begin
                            px_out         <= {raw10_p3[9:2], raw10_p3[9:2], raw10_p3[9:2]};
                            px_valid       <= 1'b1;
                            px_last        <= last_pending;
                            raw10_emitting <= 1'b0;
                            raw10_out_idx  <= 2'd0;
                        end
                    endcase
                end else if (s_axis_tvalid) begin
                    // Shift in up to 3 bytes
                    case (byte_count)
                        3'd0: begin
                            byte_buf[7:0]   <= s_axis_tdata[7:0];
                            byte_buf[15:8]  <= s_axis_tdata[15:8];
                            byte_buf[23:16] <= s_axis_tdata[23:16];
                            byte_count      <= 3'd3;
                        end

                        3'd3: begin
                            byte_buf[31:24] <= s_axis_tdata[7:0];
                            byte_buf[39:32] <= s_axis_tdata[15:8];
                            
                            // We now have 5 complete bytes! Emit Pixel 0 immediately
                            px_out         <= {s_axis_tdata[7:0], s_axis_tdata[7:0], s_axis_tdata[7:0]};
                            px_valid       <= 1'b1;
                            raw10_emitting <= 1'b1;
                            raw10_out_idx  <= 2'd1;
                            last_pending   <= s_axis_tlast;

                            // Save remaining byte (byte 5) into position 0 of next group
                            byte_buf[7:0]  <= s_axis_tdata[23:16];
                            byte_count     <= 3'd1;
                        end

                        3'd1: begin
                            byte_buf[15:8]  <= s_axis_tdata[7:0];
                            byte_buf[23:16] <= s_axis_tdata[15:8];
                            byte_buf[31:24] <= s_axis_tdata[23:16];
                            byte_count      <= 3'd4;
                        end

                        3'd4: begin
                            byte_buf[39:32] <= s_axis_tdata[7:0];
                            
                            // 5 bytes complete! Emit Pixel 0
                            px_out         <= {byte_buf[7:0], byte_buf[7:0], byte_buf[7:0]};
                            px_valid       <= 1'b1;
                            raw10_emitting <= 1'b1;
                            raw10_out_idx  <= 2'd1;
                            last_pending   <= s_axis_tlast;

                            // Save remaining 2 bytes into position 0 & 1 of next group
                            byte_buf[7:0]   <= s_axis_tdata[15:8];
                            byte_buf[15:8]  <= s_axis_tdata[23:16];
                            byte_count      <= 3'd2;
                        end

                        3'd2: begin
                            byte_buf[23:16] <= s_axis_tdata[7:0];
                            byte_buf[31:24] <= s_axis_tdata[15:8];
                            byte_buf[39:32] <= s_axis_tdata[23:16];

                            // 5 bytes complete! Emit Pixel 0
                            px_out         <= {byte_buf[7:0], byte_buf[7:0], byte_buf[7:0]};
                            px_valid       <= 1'b1;
                            raw10_emitting <= 1'b1;
                            raw10_out_idx  <= 2'd1;
                            last_pending   <= s_axis_tlast;

                            byte_count     <= 3'd0;
                        end
                    endcase
                end
            end else if (s_axis_tvalid) begin
                // Pass-through for RGB888 / RAW8
                case (data_type)
                    DT_RGB888: begin
                        px_out   <= s_axis_tdata;
                        px_valid <= 1'b1;
                        px_last  <= s_axis_tlast;
                    end

                    DT_RAW8: begin
                        px_out   <= {s_axis_tdata[7:0], s_axis_tdata[7:0], s_axis_tdata[7:0]};
                        px_valid <= 1'b1;
                        px_last  <= s_axis_tlast;
                    end

                    default: begin
                        px_out   <= s_axis_tdata;
                        px_valid <= 1'b1;
                        px_last  <= s_axis_tlast;
                    end
                endcase
            end
        end
    end

endmodule
