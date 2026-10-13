`timescale 1ns/1ps
// =============================================================================
// lifi_rx_aligner.v
// Li-Fi 1-Bit Serial Symbol Aligner
//
// Samples incoming 1-bit pd_rx_serial stream on clk_bit (10x clock).
// Searches for K.28.5 Comma pattern (0011111xxx or 1100000xxx) to establish word alignment.
// Outputs aligned 10-bit symbols on clk_cdr (1x clock).
// =============================================================================
module lifi_rx_aligner (
    input  wire       clk_bit,        // 10x Serial Bit Clock (2.0 GHz)
    input  wire       clk_cdr,        // 1x Symbol Clock (200 MHz)
    input  wire       rst_n,
    input  wire       pd_rx_serial,   // 1-bit optical serial input
    
    output reg  [9:0] aligned_10b_out,
    output reg        aligned_valid,
    output reg        aligned_lock
);

    reg [19:0] shift_reg;
    reg [3:0]  bit_cnt;
    reg [3:0]  comma_pos;
    reg        locked;

    // Search 20-bit window for 7-bit K.28.5 Comma pattern:
    // RD-: 0011111 (0x1F)
    // RD+: 1100000 (0x60)
    integer i;
    reg [3:0] found_pos;
    reg       found;

    always @(*) begin
        found     = 1'b0;
        found_pos = 4'd0;
        for (i = 0; i <= 9; i = i + 1) begin
            if (!found) begin
                if (shift_reg[i +: 7] == 7'b0011111 || shift_reg[i +: 7] == 7'b1100000) begin
                    found     = 1'b1;
                    found_pos = i[3:0];
                end
            end
        end
    end

    // 1-bit Serial Sampling & Comma Detection (clk_bit domain)
    always @(posedge clk_bit or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg       <= 20'b0;
            aligned_10b_out <= 10'b0;
            aligned_valid   <= 1'b0;
            aligned_lock    <= 1'b0;
            comma_pos       <= 4'd0;
            locked          <= 1'b0;
            bit_cnt         <= 4'd0;
        end else begin
            shift_reg     <= {shift_reg[18:0], pd_rx_serial};
            aligned_valid <= 1'b0;

            if (found && !locked) begin
                locked       <= 1'b1;
                comma_pos    <= found_pos;
                aligned_lock <= 1'b1;
                bit_cnt      <= 4'd0;
            end else if (locked) begin
                if (bit_cnt == 4'd9) begin
                    aligned_10b_out <= shift_reg[comma_pos +: 10];
                    aligned_valid   <= 1'b1;
                    bit_cnt         <= 4'd0;
                end else begin
                    bit_cnt         <= bit_cnt + 1'b1;
                end
            end
        end
    end

endmodule
