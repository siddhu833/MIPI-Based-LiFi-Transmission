`timescale 1ns/1ps
// =============================================================================
// mipi_hdr_parser.v
// RX-side MIPI CSI-2 Header Parser (24-bit AXI-Stream Input)
//
// Extracts data_id[7:0] and word_count[15:0] from header bytes at clk_sys.
// Passes 24-bit payload words to pixel_unpack.
// =============================================================================
module mipi_hdr_parser (
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Stream Input from Async FIFO (24-bit @ clk_sys)
    input  wire [23:0] s_axis_tdata,
    input  wire [2:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // Header info outputs
    output reg  [7:0]  data_id,
    output reg  [15:0] word_count,
    output reg         hdr_valid,

    // AXI-Stream Payload output to Pixel Unpacker (24-bit)
    output reg  [23:0] m_axis_tdata,
    output reg  [2:0]  m_axis_tkeep,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    // FSM States
    localparam IDLE    = 1'b0;
    localparam PAYLOAD = 1'b1;

    reg state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            data_id       <= 8'h00;
            word_count    <= 16'd0;
            hdr_valid     <= 1'b0;
            m_axis_tdata  <= 24'd0;
            m_axis_tkeep  <= 3'b000;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            hdr_valid <= 1'b0;

            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end

            if (s_axis_tvalid && s_axis_tready) begin
                case (state)
                    IDLE: begin
                        // First word contains header bytes: tdata[7:0] = data_id, tdata[23:8] = word_count
                        data_id       <= s_axis_tdata[7:0];
                        word_count    <= s_axis_tdata[23:8];
                        hdr_valid     <= 1'b1;

                        if (!s_axis_tlast) begin
                            state <= PAYLOAD;
                        end
                    end

                    PAYLOAD: begin
                        m_axis_tdata  <= s_axis_tdata;
                        m_axis_tkeep  <= s_axis_tkeep;
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast  <= s_axis_tlast;

                        if (s_axis_tlast) begin
                            state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end

endmodule
