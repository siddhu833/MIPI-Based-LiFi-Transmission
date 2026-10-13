`timescale 1ns/1ps
// =============================================================================
// encoder_8b10b.v
// Standard IBM 8b/10b Encoder with Running Disparity
//
// Ports:
//   d_in[7:0]  : 8-bit data input (bit 7=MSB=H, bit 0=LSB=A)
//   k_in       : 1 = K-code, 0 = D-code
//   valid_in   : input data is valid this cycle
//   q_out[9:0] : 10-bit encoded output (bit 9 transmitted first = 'a')
//   valid_out  : output is valid
//   rd_out     : running disparity after this word (0=RD-, 1=RD+)
//
// K-codes supported:
//   K.28.5 (0xBC, k_in=1) — Comma character. Used for Start-of-Packet.
//   K.28.1 (0x3C, k_in=1) — Idle character. Used for End-of-Packet.
// =============================================================================
module encoder_8b10b (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] d_in,
    input  wire       k_in,
    input  wire       valid_in,
    output reg  [9:0] q_out,
    output reg        valid_out,
    output wire       rd_out
);

// Running disparity: 0 = RD-,  1 = RD+
reg rd;
assign rd_out = rd;

// Split 8-bit input into 5b (EDCBA=d_in[4:0]) and 3b (HGF=d_in[7:5])
wire [4:0] edcba = d_in[4:0];
wire [2:0] hgf   = d_in[7:5];

// Intermediate combinational wires
reg [5:0] sx;    // 5b->6b encoded output
reg       rd_x;  // running disparity after the 6-bit sub-block
reg [3:0] sy;    // 3b->4b encoded output
reg       rd_y;  // running disparity after the 4-bit sub-block

// D.17, D.18, D.20 need alternate y=7 encoding to avoid comma generation
wire is_special = !k_in && (edcba == 5'b10001 ||
                             edcba == 5'b10010 ||
                             edcba == 5'b10100);

// -------------------------------------------------------------------------
// 5b/6b lookup table  (covers all 32 D codes; K.28.x hard-coded separately)
// case key = {current_rd, edcba}
// -------------------------------------------------------------------------
always @(*) begin
    case ({rd, edcba})
        // ---- RD- (rd=0) ----
        {1'b0,5'b00000}: begin sx=6'b100111; rd_x=1'b1; end // D.0
        {1'b0,5'b00001}: begin sx=6'b011101; rd_x=1'b1; end // D.1
        {1'b0,5'b00010}: begin sx=6'b101101; rd_x=1'b1; end // D.2
        {1'b0,5'b00011}: begin sx=6'b110001; rd_x=1'b0; end // D.3
        {1'b0,5'b00100}: begin sx=6'b110101; rd_x=1'b1; end // D.4
        {1'b0,5'b00101}: begin sx=6'b101001; rd_x=1'b0; end // D.5
        {1'b0,5'b00110}: begin sx=6'b011001; rd_x=1'b0; end // D.6
        {1'b0,5'b00111}: begin sx=6'b111000; rd_x=1'b0; end // D.7
        {1'b0,5'b01000}: begin sx=6'b111001; rd_x=1'b1; end // D.8
        {1'b0,5'b01001}: begin sx=6'b100101; rd_x=1'b0; end // D.9
        {1'b0,5'b01010}: begin sx=6'b010101; rd_x=1'b0; end // D.10
        {1'b0,5'b01011}: begin sx=6'b110100; rd_x=1'b0; end // D.11
        {1'b0,5'b01100}: begin sx=6'b001101; rd_x=1'b0; end // D.12
        {1'b0,5'b01101}: begin sx=6'b101100; rd_x=1'b0; end // D.13
        {1'b0,5'b01110}: begin sx=6'b011100; rd_x=1'b0; end // D.14
        {1'b0,5'b01111}: begin sx=6'b010111; rd_x=1'b1; end // D.15
        {1'b0,5'b10000}: begin sx=6'b011011; rd_x=1'b1; end // D.16
        {1'b0,5'b10001}: begin sx=6'b100011; rd_x=1'b0; end // D.17
        {1'b0,5'b10010}: begin sx=6'b010011; rd_x=1'b0; end // D.18
        {1'b0,5'b10011}: begin sx=6'b110010; rd_x=1'b0; end // D.19
        {1'b0,5'b10100}: begin sx=6'b001011; rd_x=1'b0; end // D.20
        {1'b0,5'b10101}: begin sx=6'b101010; rd_x=1'b0; end // D.21
        {1'b0,5'b10110}: begin sx=6'b011010; rd_x=1'b0; end // D.22
        {1'b0,5'b10111}: begin sx=6'b111010; rd_x=1'b1; end // D.23
        {1'b0,5'b11000}: begin sx=6'b110011; rd_x=1'b1; end // D.24
        {1'b0,5'b11001}: begin sx=6'b100110; rd_x=1'b0; end // D.25
        {1'b0,5'b11010}: begin sx=6'b010110; rd_x=1'b0; end // D.26
        {1'b0,5'b11011}: begin sx=6'b110110; rd_x=1'b1; end // D.27
        {1'b0,5'b11100}: begin sx=6'b001110; rd_x=1'b0; end // D.28 (K.28 overrides this)
        {1'b0,5'b11101}: begin sx=6'b101110; rd_x=1'b1; end // D.29
        {1'b0,5'b11110}: begin sx=6'b011110; rd_x=1'b1; end // D.30
        {1'b0,5'b11111}: begin sx=6'b101011; rd_x=1'b1; end // D.31
        // ---- RD+ (rd=1) ----
        {1'b1,5'b00000}: begin sx=6'b011000; rd_x=1'b0; end // D.0
        {1'b1,5'b00001}: begin sx=6'b100010; rd_x=1'b0; end // D.1
        {1'b1,5'b00010}: begin sx=6'b010010; rd_x=1'b0; end // D.2
        {1'b1,5'b00011}: begin sx=6'b110001; rd_x=1'b1; end // D.3
        {1'b1,5'b00100}: begin sx=6'b001010; rd_x=1'b0; end // D.4
        {1'b1,5'b00101}: begin sx=6'b101001; rd_x=1'b1; end // D.5
        {1'b1,5'b00110}: begin sx=6'b011001; rd_x=1'b1; end // D.6
        {1'b1,5'b00111}: begin sx=6'b000111; rd_x=1'b0; end // D.7
        {1'b1,5'b01000}: begin sx=6'b000110; rd_x=1'b0; end // D.8
        {1'b1,5'b01001}: begin sx=6'b100101; rd_x=1'b1; end // D.9
        {1'b1,5'b01010}: begin sx=6'b010101; rd_x=1'b1; end // D.10
        {1'b1,5'b01011}: begin sx=6'b110100; rd_x=1'b1; end // D.11
        {1'b1,5'b01100}: begin sx=6'b001101; rd_x=1'b1; end // D.12
        {1'b1,5'b01101}: begin sx=6'b101100; rd_x=1'b1; end // D.13
        {1'b1,5'b01110}: begin sx=6'b011100; rd_x=1'b1; end // D.14
        {1'b1,5'b01111}: begin sx=6'b101000; rd_x=1'b0; end // D.15
        {1'b1,5'b10000}: begin sx=6'b100100; rd_x=1'b0; end // D.16
        {1'b1,5'b10001}: begin sx=6'b100011; rd_x=1'b1; end // D.17
        {1'b1,5'b10010}: begin sx=6'b010011; rd_x=1'b1; end // D.18
        {1'b1,5'b10011}: begin sx=6'b110010; rd_x=1'b1; end // D.19
        {1'b1,5'b10100}: begin sx=6'b001011; rd_x=1'b1; end // D.20
        {1'b1,5'b10101}: begin sx=6'b101010; rd_x=1'b1; end // D.21
        {1'b1,5'b10110}: begin sx=6'b011010; rd_x=1'b1; end // D.22
        {1'b1,5'b10111}: begin sx=6'b000101; rd_x=1'b0; end // D.23
        {1'b1,5'b11000}: begin sx=6'b001100; rd_x=1'b0; end // D.24
        {1'b1,5'b11001}: begin sx=6'b100110; rd_x=1'b1; end // D.25
        {1'b1,5'b11010}: begin sx=6'b010110; rd_x=1'b1; end // D.26
        {1'b1,5'b11011}: begin sx=6'b001001; rd_x=1'b0; end // D.27
        {1'b1,5'b11100}: begin sx=6'b001110; rd_x=1'b1; end // D.28 (K.28 overrides)
        {1'b1,5'b11101}: begin sx=6'b010001; rd_x=1'b0; end // D.29
        {1'b1,5'b11110}: begin sx=6'b100001; rd_x=1'b0; end // D.30
        {1'b1,5'b11111}: begin sx=6'b010100; rd_x=1'b0; end // D.31
        default:         begin sx=6'b000000; rd_x=rd;   end
    endcase

    // K.28.x overrides 5b/6b: uses 001111 (RD-) or 110000 (RD+)
    if (k_in && edcba == 5'b11100) begin
        sx   = rd ? 6'b110000 : 6'b001111;
        rd_x = ~rd; // always non-neutral, always flips
    end
end

// -------------------------------------------------------------------------
// 3b/4b lookup table
// case key = {rd_x, hgf}
// K.x.5 and K.x.1 have alternate codes vs D
// D.17.7, D.18.7, D.20.7 use alternate y=7 codes to avoid comma generation
// -------------------------------------------------------------------------
always @(*) begin
    case ({rd_x, hgf})
        {1'b0,3'b000}: begin sy=4'b1011; rd_y=1'b1; end // D/K.x.0 RD-
        {1'b0,3'b001}: begin sy=k_in?4'b0110:4'b1001; rd_y=1'b0; end // D.x.1=1001, K.x.1=0110
        {1'b0,3'b010}: begin sy=4'b0101; rd_y=1'b0; end // D/K.x.2 RD-
        {1'b0,3'b011}: begin sy=4'b0011; rd_y=1'b0; end // D/K.x.3 RD-
        {1'b0,3'b100}: begin sy=4'b1101; rd_y=1'b1; end // D/K.x.4 RD-
        {1'b0,3'b101}: begin sy=k_in?4'b0101:4'b1010; rd_y=1'b0; end // D.x.5=1010,K.x.5=0101
        {1'b0,3'b110}: begin sy=k_in?4'b1001:4'b0110; rd_y=1'b0; end // D.x.6=0110,K.x.6=1001
        {1'b0,3'b111}: begin                                           // D/K.x.7 RD-
            sy   = (k_in || !is_special) ? 4'b1110 : 4'b0111;
            rd_y = 1'b1;
        end
        {1'b1,3'b000}: begin sy=4'b0100; rd_y=1'b0; end // D/K.x.0 RD+
        {1'b1,3'b001}: begin sy=k_in?4'b1001:4'b1001; rd_y=1'b1; end // both use 1001 at RD+
        {1'b1,3'b010}: begin sy=4'b0101; rd_y=1'b1; end // D/K.x.2 RD+
        {1'b1,3'b011}: begin sy=4'b1100; rd_y=1'b1; end // D/K.x.3 RD+
        {1'b1,3'b100}: begin sy=4'b0010; rd_y=1'b0; end // D/K.x.4 RD+
        {1'b1,3'b101}: begin sy=4'b1010; rd_y=1'b1; end // both use 1010 at RD+
        {1'b1,3'b110}: begin sy=4'b0110; rd_y=1'b1; end // both use 0110 at RD+
        {1'b1,3'b111}: begin                                           // D/K.x.7 RD+
            sy   = (k_in || !is_special) ? 4'b0001 : 4'b1000;
            rd_y = 1'b0;
        end
        default: begin sy=4'b0000; rd_y=rd_x; end
    endcase
end

// -------------------------------------------------------------------------
// Output register + running disparity update
// -------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd        <= 1'b0; // start at RD-
        q_out     <= 10'b0;
        valid_out <= 1'b0;
    end else begin
        valid_out <= valid_in;
        if (valid_in) begin
            q_out <= {sx, sy};   // abcdeifghj = {sx[5:0], sy[3:0]}
            rd    <= rd_y;
        end
    end
end

endmodule
