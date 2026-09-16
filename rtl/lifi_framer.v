`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: siddardhareddy duggu
// Module Name: lifi_framer
// Project Name: lifi tx
// Description: Wraps MIPI bytes in Li-Fi framing (SOP, Payload, EOF, IDLE).
//              WAITS for tx_ready from PISO before processing the next byte.
//////////////////////////////////////////////////////////////////////////////////

module lifi_framer(
    input           clk, 
    input           rst,
    input wire [7:0] fifo_dout,
    input wire      fifo_empty,
    input wire      fifo_last,
    input wire      tx_ready,    // <--- ADDED: Handshake from PISO
    output reg      fifo_rd_en,
    output reg [7:0] enc_data,
    output reg      enc_is_k
);

    reg [1:0] state;
    localparam IDLE    = 2'b00, 
               S_PKT   = 2'b01, 
               PAYLOAD = 2'b10, 
               E_PKT   = 2'b11;

    // Define the Control Characters (K-characters)
    localparam [7:0] IDLE_CHAR = 8'hBC; // K.28.5 (Idle pattern)
    localparam [7:0] SOP_CHAR  = 8'hFB; // K.27.7 (Start of Packet)
    localparam [7:0] EOF_CHAR  = 8'hFD; // K.29.7 (End of Packet)
    
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            fifo_rd_en <= 1'b0;
            enc_data   <= IDLE_CHAR;
            enc_is_k   <= 1'b1;
            state      <= IDLE;
        end else begin 
            case (state) 
                
                // ----------------------------------------
                // State 1: Waiting for data from FIFO
                // ----------------------------------------
                IDLE: begin
                    enc_data <= IDLE_CHAR;
                    enc_is_k <= 1'b1;
                    fifo_rd_en <= 1'b0; 
                    
                    // ONLY move to SOP if FIFO has data AND PISO is ready to accept it
                    if (!fifo_empty && tx_ready) begin 
                        state <= S_PKT;
                    end
                end
                
                // ----------------------------------------
                // State 2: Send Start of Packet marker
                // ----------------------------------------
                S_PKT: begin
                    enc_data <= SOP_CHAR;
                    enc_is_k <= 1'b1;
                    fifo_rd_en <= 1'b0; 
                    
                    // ONLY move to PAYLOAD when PISO has finished shifting the SOP char
                    if (tx_ready) begin 
                        state <= PAYLOAD;
                    end
                end
                
                // ----------------------------------------
                // State 3: Stream raw MIPI bytes from FIFO
                // ----------------------------------------
                PAYLOAD: begin
                    enc_data <= fifo_dout; 
                    enc_is_k <= 1'b0;      
                    
                    // ONLY read the next byte from FIFO when PISO is ready for it!
                    // This prevents skipping bytes.
                    if (tx_ready) begin 
                        fifo_rd_en <= 1'b1;
                        if (fifo_last) begin
                            state <= E_PKT;
                        end
                    end else begin
                        // If PISO is busy shifting, hold the read enable low and wait
                        fifo_rd_en <= 1'b0; 
                    end
                end
                
                // ----------------------------------------
                // State 4: Send End of Packet marker
                // ----------------------------------------
                E_PKT: begin
                    enc_data <= EOF_CHAR;
                    enc_is_k <= 1'b1;
                    fifo_rd_en <= 1'b0; 
                    
                    // ONLY go back to IDLE when PISO is done shifting the EOF char
                    if (tx_ready) begin 
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
                
            endcase
        end
    end

endmodule