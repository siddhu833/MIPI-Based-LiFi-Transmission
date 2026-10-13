`timescale 1ns/1ps
// =============================================================================
// lifi_framer.v
// Li-Fi Framer for MIPI CSI-2 Transmission
//
// Uses phy_sot and phy_eot signals from D-PHY to insert framing characters:
//   - Preamble (0x55, 2 cycles) + COMMA K.28.5 (0xBC, k_out=1) at Start-of-Packet (SOT)
//   - Passes payload bytes (k_out=0) during active transmission
//   - Inserts IDLE K.28.1 (0x3C, k_out=1) at End-of-Packet (EOT) and during inter-packet gap
// =============================================================================
module lifi_framer (
    input  wire       clk,
    input  wire       rst_n,
    
    // Input from PHY / Async FIFO
    input  wire [7:0] phy_byte,
    input  wire       phy_valid,
    input  wire       phy_sot,
    input  wire       phy_eot,
    
    // Output to 8b/10b encoder
    output reg  [7:0] data_out,
    output reg        k_out,
    output reg        valid_out
);

    // K-code constants
    localparam [7:0] K_COMMA = 8'hBC; // K.28.5 (Comma / SOT marker)
    localparam [7:0] K_IDLE  = 8'h3C; // K.28.1 (Idle / EOT marker)
    localparam [7:0] PREAMBLE= 8'h55; // Alternating 01010101 pattern for CDR locking

    // FSM States
    localparam IDLE         = 2'd0;
    localparam SEND_PREAMBLE= 2'd1;
    localparam SEND_COMMA   = 2'd2;
    localparam STREAM_DATA  = 2'd3;

    reg [1:0] state;
    reg [1:0] preamble_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            preamble_cnt <= 2'd0;
            data_out     <= K_IDLE;
            k_out        <= 1'b1;
            valid_out    <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    data_out  <= K_IDLE;
                    k_out     <= 1'b1;
                    valid_out <= 1'b1;

                    if (phy_sot) begin
                        state        <= SEND_PREAMBLE;
                        preamble_cnt <= 2'd0;
                        data_out     <= PREAMBLE;
                        k_out        <= 1'b0;
                    end
                end

                SEND_PREAMBLE: begin
                    data_out  <= PREAMBLE;
                    k_out     <= 1'b0;
                    valid_out <= 1'b1;

                    if (preamble_cnt == 2'd1) begin
                        state <= SEND_COMMA;
                    end else begin
                        preamble_cnt <= preamble_cnt + 1'b1;
                    end
                end

                SEND_COMMA: begin
                    data_out  <= K_COMMA;
                    k_out     <= 1'b1; // K.28.5 Comma
                    valid_out <= 1'b1;
                    state     <= STREAM_DATA;
                end

                STREAM_DATA: begin
                    if (phy_eot) begin
                        data_out  <= K_IDLE;
                        k_out     <= 1'b1;
                        valid_out <= 1'b1;
                        state     <= IDLE;
                    end else if (phy_valid) begin
                        data_out  <= phy_byte;
                        k_out     <= 1'b0;
                        valid_out <= 1'b1;
                    end else begin
                        // Idle filler between bytes if phy_valid drops temporarily
                        data_out  <= K_IDLE;
                        k_out     <= 1'b1;
                        valid_out <= 1'b1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
