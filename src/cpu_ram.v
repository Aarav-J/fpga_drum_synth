// PicoRV32 instruction + data RAM — combined, single-port, word-addressed.
//
// Same technique as sine_rom.v: a synthesizable array inferred as block RAM,
// initialized at synthesis time from a hex file.
//
// 1 cycle read latency (rdata is registered). PicoRV32's native memory
// interface tolerates this as long as mem_ready is held low until the data
// is valid — see cpu_bus.v for how that's handled.
//
// WORDS=1024 → 4096 bytes = 4 KB. Must match STACKADDR / sections.lds.

module cpu_ram #(
    parameter integer WORDS = 1024
) (
    input  wire        clk,
    input  wire [3:0]  wen,    // byte write-enable, one bit per byte lane
    input  wire [9:0]  addr,   // word address (0 .. WORDS-1)
    input  wire [31:0] wdata,
    output reg  [31:0] rdata
);

    reg [31:0] mem [0:WORDS-1];

    initial $readmemh("firmware/firmware.hex", mem);

    always @(posedge clk) begin
        rdata <= mem[addr];
        if (wen[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
        if (wen[1]) mem[addr][15: 8] <= wdata[15: 8];
        if (wen[2]) mem[addr][23:16] <= wdata[23:16];
        if (wen[3]) mem[addr][31:24] <= wdata[31:24];
    end

endmodule
