`timescale 1ns/1ps
// =============================================================================
// axis_asyncc_fifo.v
// Asymmetric AXI-Stream Asynchronous FIFO Bridge
//
// Write side: 8-bit  @ s_axis_aclk (clk_cdr)
// Read side:  24-bit @ m_axis_aclk (clk_sys)
//
// Accumulates 3 incoming bytes into a 24-bit word before pushing to the core async FIFO.
// Handles partial words via tkeep[2:0] when tlast occurs before 3 bytes accumulate.
// =============================================================================
module axis_asyncc_fifo #(
    parameter depth = 4096
)(
    // Write Domain (8-bit @ clk_cdr)
    input  wire        s_axis_aclk,
    input  wire        s_axis_aresetn,
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // Read Domain (24-bit @ clk_sys)
    input  wire        m_axis_aclk,
    input  wire        m_axis_aresetn,
    output wire [23:0] m_axis_tdata,
    output wire [2:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // -------------------------------------------------------------------------
    // Write Side Accumulator (8-bit -> 24-bit)
    // -------------------------------------------------------------------------
    reg [23:0] wr_buf;
    reg [1:0]  wr_cnt;
    reg [27:0] fifo_din;
    reg        fifo_wr;
    wire       fifo_full;

    assign s_axis_tready = !fifo_full;

    always @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn) begin
            wr_buf   <= 24'd0;
            wr_cnt   <= 2'd0;
            fifo_din <= 28'd0;
            fifo_flush_req <= 1'b0;
            fifo_wr  <= 1'b0;
        end else begin
            fifo_wr <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                case (wr_cnt)
                    2'd0: begin
                        wr_buf[7:0] <= s_axis_tdata;
                        if (s_axis_tlast) begin
                            fifo_din <= {1'b1, 3'b001, 16'h0000, s_axis_tdata};
                            fifo_wr  <= 1'b1;
                            wr_cnt   <= 2'd0;
                        end else begin
                            wr_cnt <= 2'd1;
                        end
                    end

                    2'd1: begin
                        wr_buf[15:8] <= s_axis_tdata;
                        if (s_axis_tlast) begin
                            fifo_din <= {1'b1, 3'b011, 8'h00, s_axis_tdata, wr_buf[7:0]};
                            fifo_wr  <= 1'b1;
                            wr_cnt   <= 2'd0;
                        end else begin
                            wr_cnt <= 2'd2;
                        end
                    end

                    2'd2: begin
                        wr_buf[23:16] <= s_axis_tdata;
                        fifo_din      <= {s_axis_tlast, 3'b111, s_axis_tdata, wr_buf[15:0]};
                        fifo_wr       <= 1'b1;
                        wr_cnt        <= 2'd0;
                    end
                endcase
            end
        end
    end

    reg fifo_flush_req;

    // -------------------------------------------------------------------------
    // Core Asynchronous FIFO (28-bit width)
    // Format: {tlast, tkeep[2:0], tdata[23:0]}
    // -------------------------------------------------------------------------
    wire [27:0] fifo_dout;
    wire        fifo_empty;
    wire        fifo_rd;

    asyncc_fifo #(
        .depth(depth),
        .width(28)
    ) fifo_core (
        .clk_w(s_axis_aclk),
        .clk_r(m_axis_aclk),
        .rst_w(!s_axis_aresetn),
        .rst_r(!m_axis_aresetn),
        .w_en(fifo_wr),
        .r_en(fifo_rd),
        .data_in(fifo_din),
        .full(fifo_full),
        .empty(fifo_empty),
        .data_out(fifo_dout)
    );

    // -------------------------------------------------------------------------
    // Read Side Skid Buffer (24-bit Output)
    // -------------------------------------------------------------------------
    reg [27:0] data_reg;
    reg        data_valid;
    reg [27:0] temp_reg;
    reg        temp_valid;
    reg        fifo_rd_d;

    wire [1:0] occupied_slots = data_valid + temp_valid + fifo_rd_d;
    assign fifo_rd = !fifo_empty && (occupied_slots < 2 || (occupied_slots == 2 && m_axis_tready));

    always @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
        if (!m_axis_aresetn) begin
            data_reg   <= 28'd0;
            data_valid <= 1'b0;
            temp_reg   <= 28'd0;
            temp_valid <= 1'b0;
            fifo_rd_d  <= 1'b0;
        end else begin
            fifo_rd_d <= fifo_rd;

            if (fifo_rd_d) begin
                if (!data_valid || (data_valid && m_axis_tready)) begin
                    if (temp_valid) begin
                        data_reg   <= temp_reg;
                        temp_reg   <= fifo_dout;
                        temp_valid <= 1'b1;
                    end else begin
                        data_reg   <= fifo_dout;
                        data_valid <= 1'b1;
                    end
                end else begin
                    temp_reg   <= fifo_dout;
                    temp_valid <= 1'b1;
                end
            end else if (temp_valid && m_axis_tready) begin
                data_reg   <= temp_reg;
                data_valid <= 1'b1;
                temp_valid <= 1'b0;
            end else if (m_axis_tready) begin
                data_valid <= 1'b0;
            end
        end
    end

    assign m_axis_tvalid = data_valid;
    assign m_axis_tdata  = data_reg[23:0];
    assign m_axis_tkeep  = data_reg[26:24];
    assign m_axis_tlast  = data_reg[27];

endmodule
