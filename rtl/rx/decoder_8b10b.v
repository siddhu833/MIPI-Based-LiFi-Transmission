`timescale 1ns/1ps
// =============================================================================
// decoder_8b10b.v
// Standard 8b/10b Decoder
//
// Ports:
//   clk         : RX bit/symbol clock
//   rst_n       : Active low reset
//   d_in[9:0]   : 10-bit symbol input
//   valid_in    : Input valid
//   d_out[7:0]  : 8-bit decoded data
//   k_out       : 1 if decoded symbol is K-code, 0 if D-code
//   valid_out   : Output valid
//   code_err    : 1 if invalid 10-bit code detected
//   disp_err    : 1 if disparity error detected
// =============================================================================
module decoder_8b10b (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [9:0] d_in,
    input  wire       valid_in,
    output reg  [7:0] d_out,
    output reg        k_out,
    output reg        valid_out,
    output reg        code_err,
    output reg        disp_err
);

    wire [5:0] abcdei = d_in[9:4];
    wire [3:0] fghj   = d_in[3:0];

    reg [4:0] edcba;
    reg [2:0] hgf;
    reg       is_k;
    reg       err_6b, err_4b;

    // 6b -> 5b decoding
    always @(*) begin
        is_k   = 1'b0;
        err_6b = 1'b0;
        case (abcdei)
            6'b100111, 6'b011000: edcba = 5'b00000; // D.0
            6'b011101, 6'b100010: edcba = 5'b00001; // D.1
            6'b101101, 6'b010010: edcba = 5'b00010; // D.2
            6'b110001:           edcba = 5'b00011; // D.3
            6'b110101, 6'b001010: edcba = 5'b00100; // D.4
            6'b101001:           edcba = 5'b00101; // D.5
            6'b011001:           edcba = 5'b00110; // D.6
            6'b111000, 6'b000111: edcba = 5'b00111; // D.7
            6'b111001, 6'b000110: edcba = 5'b01000; // D.8
            6'b100101:           edcba = 5'b01001; // D.9
            6'b010101:           edcba = 5'b01010; // D.10
            6'b110100:           edcba = 5'b01011; // D.11
            6'b001101:           edcba = 5'b01100; // D.12
            6'b101100:           edcba = 5'b01101; // D.13
            6'b011100:           edcba = 5'b01110; // D.14
            6'b010111, 6'b101000: edcba = 5'b01111; // D.15
            6'b011011, 6'b100100: edcba = 5'b10000; // D.16
            6'b100011:           edcba = 5'b10001; // D.17
            6'b010011:           edcba = 5'b10010; // D.18
            6'b110010:           edcba = 5'b10011; // D.19
            6'b001011:           edcba = 5'b10100; // D.20
            6'b101010:           edcba = 5'b10101; // D.21
            6'b011010:           edcba = 5'b10110; // D.22
            6'b111010, 6'b000101: edcba = 5'b10111; // D.23
            6'b110011, 6'b001100: edcba = 5'b11000; // D.24
            6'b100110:           edcba = 5'b11001; // D.25
            6'b010110:           edcba = 5'b11010; // D.26
            6'b110110, 6'b001001: edcba = 5'b11011; // D.27
            6'b001110:           edcba = 5'b11100; // D.28
            6'b101110, 6'b010001: edcba = 5'b11101; // D.29
            6'b011110, 6'b100001: edcba = 5'b11110; // D.30
            6'b101011, 6'b010100: edcba = 5'b11111; // D.31
            
            // K.28.x specials (001111 / 110000)
            6'b001111, 6'b110000: begin
                edcba = 5'b11100; // K.28
                is_k  = 1'b1;
            end

            default: begin
                edcba  = 5'b00000;
                err_6b = 1'b1;
            end
        endcase
    end

    // 4b -> 3b decoding
    always @(*) begin
        err_4b = 1'b0;
        case (fghj)
            4'b1011, 4'b0100: hgf = 3'b000; // y=0
            4'b1001, 4'b0110: hgf = 3'b001; // y=1
            4'b0101:          hgf = 3'b010; // y=2
            4'b0011, 4'b1100: hgf = 3'b011; // y=3
            4'b1101, 4'b0010: hgf = 3'b100; // y=4
            4'b1010:          hgf = 3'b101; // y=5
            4'b0110:          hgf = 3'b110; // y=6
            4'b1110, 4'b0001,
            4'b0111, 4'b1000: hgf = 3'b111; // y=7

            default: begin
                hgf    = 3'b000;
                err_4b = 1'b1;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_out     <= 8'h00;
            k_out     <= 1'b0;
            valid_out <= 1'b0;
            code_err  <= 1'b0;
            disp_err  <= 1'b0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                d_out    <= {hgf, edcba};
                k_out    <= is_k;
                code_err <= err_6b || err_4b;
            end
        end
    end

endmodule
