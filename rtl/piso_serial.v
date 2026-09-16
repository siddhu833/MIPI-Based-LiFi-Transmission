`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.09.2026 15:36:42
// Design Name: siddhardhareddy duggu
// Module Name: piso_serial
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: siddardhareddy duggu
// Module Name: piso_serializer
// Project Name: lifi tx
// Description: Takes 10-bit parallel data and shifts it out serially to the LED.
//////////////////////////////////////////////////////////////////////////////////

module piso_serializer(
    input wire        clk,
    input wire        rst,
    input wire [9:0]  data_in,    // 10-bit encoded word from 8b/10b Encoder
    output reg        tx_ready,   // 1 = PISO is ready for a new word, 0 = Busy shifting
    output wire       led_data_out // 1-bit serial stream to the LED
);

    reg [9:0] shift_reg;
    reg [3:0] bit_cnt; // Counts from 0 to 9
    
    // The LED outputs the MSB of the shift register.
    // When inactive, it outputs 0 (LED OFF).
    assign led_data_out = (bit_cnt != 4'd0) ? shift_reg[9] : 1'b0;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            shift_reg <= 10'b0;
            bit_cnt   <= 4'd0;
            tx_ready  <= 1'b1; // Start ready to load
        end else begin
            if (bit_cnt == 4'd0) begin
                // LOAD PHASE: Load the new 10-bit word into the shift register
                shift_reg <= data_in;
                bit_cnt   <= 4'd9;  // Prepare to shift 9 times
                tx_ready  <= 1'b0;  // Busy. Tell Framer/Encoder to hold.
            end else begin
                // SHIFT PHASE: Shift left by 1 bit (MSB goes out first)
                shift_reg <= {shift_reg[8:0], 1'b0};
                bit_cnt   <= bit_cnt - 1'b1;
                
                // When bit_cnt reaches 1, the next cycle is the last bit.
                // On the cycle after that, we need to be ready to load again.
                if (bit_cnt == 4'd1) begin
                    tx_ready <= 1'b1; // Tell Framer to prepare the NEXT word!
                end
            end
        end
    end

endmodule