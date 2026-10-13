// =============================================================================
// MIPI LLP Passthrough Module
// All ECC and CRC checks have been moved to the Li-Fi RX side.
// This module is a pure cut-through passthrough with zero logic overhead.
// =============================================================================
module csi2_rx_llp_sf (
    input  wire        clk,
    input  wire        rst_n,

    // Input from MIPI D-PHY
    input  wire [7:0]  phy_byte,
    input  wire        phy_valid,

    // Output to Li-Fi TX Async FIFO
    output wire [7:0]  m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // Pure cut-through passthrough
    assign m_axis_tdata  = phy_byte;
    assign m_axis_tvalid = phy_valid;
    
    // Note: You currently have tlast hardcoded to 0. 
    // If your Async FIFO doesn't need tlast, you can even remove this port!
    assign m_axis_tlast  = 1'b0;

endmodule