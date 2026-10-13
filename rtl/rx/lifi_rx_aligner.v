`timescale 1ns/1ps
// =============================================================================
// lifi_rx_aligner.v
// Li-Fi 1-Bit Serial Symbol Aligner
//
// Samples the 1-bit serial stream on clk_bit (10x clk_cdr, phase-related) MSB-first
// (bit 'a' of each 8b/10b symbol arrives first, so the newest bit is shift_reg[0]).
// A K.28.x comma (a..f = 0011111 or 1100000) in shift_reg[9:3] marks a symbol
// boundary; after that a 10-bit word is registered every 10 clk_bit cycles.
//
// The registered word is held stable for 10 clk_bit cycles (one clk_cdr period),
// so the clk_cdr-domain decoder samples it without a pulse-crossing problem.
// aligned_valid stays high once locked (one new symbol per clk_cdr cycle).
// =============================================================================
module lifi_rx_aligner (
    input  wire       clk_bit,        // 10x serial bit clock
    input  wire       clk_cdr,        // 1x symbol clock (same source as clk_bit/10)
    input  wire       rst_n,
    input  wire       pd_rx_serial,   // 1-bit optical serial input

    output reg  [9:0] aligned_10b_out,
    output reg        aligned_valid,
    output reg        aligned_lock
);

    reg [9:0] shift_reg;
    reg [3:0] bit_cnt;
    reg       locked;

    wire comma = (shift_reg[9:3] == 7'b0011111) || (shift_reg[9:3] == 7'b1100000);

    always @(posedge clk_bit or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg       <= 10'b0;
            aligned_10b_out <= 10'b0;
            aligned_valid   <= 1'b0;
            aligned_lock    <= 1'b0;
            bit_cnt         <= 4'd0;
            locked          <= 1'b0;
        end else begin
            shift_reg <= {shift_reg[8:0], pd_rx_serial};

            if (!locked) begin
                if (comma) begin
                    // shift_reg holds a complete, aligned symbol right now
                    locked          <= 1'b1;
                    aligned_lock    <= 1'b1;
                    aligned_valid   <= 1'b1;
                    aligned_10b_out <= shift_reg;
                    bit_cnt         <= 4'd1;
                end
            end else begin
                if (bit_cnt == 4'd9) begin
                    aligned_10b_out <= {shift_reg[8:0], pd_rx_serial};
                    bit_cnt         <= 4'd0;
                end else begin
                    bit_cnt         <= bit_cnt + 1'b1;
                end
            end
        end
    end

endmodule
