`timescale 1ns/1ps
// =============================================================================
// ecc_crc_checker.v
// RX-side Cut-Through Header ECC Correction and Payload CRC Checker
//
// Receives 8-bit stream from 8b/10b decoder at clk_cdr:
//   1. Buffers first 4 header bytes to run ECC check & correction
//   2. Outputs corrected header bytes immediately
//   3. Passes payload bytes through directly (cut-through)
//   4. Calculates CRC16 in parallel and asserts crc_error post-hoc at EOP
// =============================================================================
module ecc_crc_checker #(
    parameter [1:0] TARGET_VC = 2'b00
)(
    input  wire        clk,
    input  wire        rst_n,

    // Input from 8b/10b decoder / aligner
    input  wire [7:0]  d_in,
    input  wire        k_in,       // 1 = K-code (Comma/Idle), 0 = Data
    input  wire        valid_in,

    // Output cut-through stream
    output reg  [7:0]  d_out,
    output reg         valid_out,
    output reg         last_out,

    // Status outputs
    output reg         ecc_ok,
    output reg         ecc_corrected,
    output reg         ecc_error,
    output reg         crc_error,
    output reg  [7:0]  data_id,
    output reg  [15:0] word_count,
    output reg         packet_done
);

    // States
    localparam IDLE    = 3'd0;
    localparam HEADER  = 3'd1;
    localparam PAYLOAD = 3'd2;
    localparam CRC_LSB = 3'd3;
    localparam CRC_MSB = 3'd4;

    reg [2:0]  state;
    reg [1:0]  hdr_cnt;
    reg [15:0] payload_cnt;

    reg [7:0] hdr_b0, hdr_b1, hdr_b2;
    wire [7:0] hdr_b3 = d_in;

    // ECC Signals
    wire [25:0] ecc_data_in = {hdr_b2[5:0], hdr_b1, hdr_b0};
    wire [5:0]  ecc_rx      = hdr_b3[5:0];
    wire [25:0] ecc_data_corr;
    wire        ecc_ok_w, ecc_corr_w, ecc_err_w;

    csi2_ecc_rx ecc_inst (
        .data_in(ecc_data_in),
        .ecc_rx(ecc_rx),
        .data_corr(ecc_data_corr),
        .ecc_ok(ecc_ok_w),
        .ecc_corrected(ecc_corr_w),
        .ecc_error(ecc_err_w)
    );

    wire [7:0] corr_data_id = ecc_data_corr[7:0];
    wire [7:0] corr_wc_lsb  = ecc_data_corr[15:8];
    wire [5:0] corr_wc_msb  = ecc_data_corr[21:16];

    // CRC Signals
    wire        crc_init = (state == HEADER) && (hdr_cnt == 2'd3) && valid_in && !ecc_err_w && (corr_data_id >= 8'h10);
    wire        crc_en   = (state == PAYLOAD) && valid_in && !k_in;
    wire [15:0] crc_calc;
    reg  [7:0]  crc_lsb;

    crc16_1021 crc_inst (
        .clk(clk),
        .rst(~rst_n),
        .init(crc_init),
        .data_valid(crc_en),
        .data_in(d_in),
        .crc_out(crc_calc)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            hdr_cnt       <= 2'd0;
            payload_cnt   <= 16'd0;
            d_out         <= 8'h00;
            valid_out     <= 1'b0;
            last_out      <= 1'b0;
            ecc_ok        <= 1'b0;
            ecc_corrected <= 1'b0;
            ecc_error     <= 1'b0;
            crc_error     <= 1'b0;
            data_id       <= 8'h00;
            word_count    <= 16'd0;
            packet_done   <= 1'b0;
        end else begin
            packet_done <= 1'b0;
            valid_out   <= 1'b0;
            last_out    <= 1'b0;

            case (state)
                IDLE: begin
                    hdr_cnt     <= 2'd0;
                    payload_cnt <= 16'd0;
                    if (valid_in && !k_in) begin
                        hdr_b0  <= d_in;
                        hdr_cnt <= 2'd1;
                        state   <= HEADER;
                    end
                end

                HEADER: begin
                    if (valid_in && !k_in) begin
                        case (hdr_cnt)
                            2'd1: begin hdr_b1 <= d_in; hdr_cnt <= 2'd2; end
                            2'd2: begin hdr_b2 <= d_in; hdr_cnt <= 2'd3; end
                            2'd3: begin
                                ecc_ok        <= ecc_ok_w;
                                ecc_corrected <= ecc_corr_w;
                                ecc_error     <= ecc_err_w;
                                data_id       <= corr_data_id;
                                word_count    <= {corr_wc_msb, corr_wc_lsb};

                                // Emit corrected header data_id immediately
                                d_out     <= corr_data_id;
                                valid_out <= 1'b1;

                                if (ecc_err_w || corr_data_id < 8'h10) begin
                                    packet_done <= 1'b1;
                                    state       <= IDLE;
                                end else begin
                                    state       <= PAYLOAD;
                                end
                            end
                        endcase
                    end
                end

                PAYLOAD: begin
                    if (valid_in && !k_in) begin
                        d_out       <= d_in;
                        valid_out   <= 1'b1;
                        payload_cnt <= payload_cnt + 1'b1;

                        if (payload_cnt == word_count - 1) begin
                            state <= CRC_LSB;
                        end
                    end
                end

                CRC_LSB: begin
                    if (valid_in && !k_in) begin
                        crc_lsb <= d_in;
                        state   <= CRC_MSB;
                    end
                end

                CRC_MSB: begin
                    if (valid_in && !k_in) begin
                        if ({d_in, crc_lsb} != crc_calc) begin
                            crc_error <= 1'b1;
                        end else begin
                            crc_error <= 1'b0;
                        end
                        last_out    <= 1'b1;
                        packet_done <= 1'b1;
                        state       <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
