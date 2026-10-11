// CPU bus — decodes PicoRV32's memory accesses into either program RAM or
// memory-mapped peripheral registers.
//
// Memory map:
//   0x0000_0000 - 0x0000_0FFF   4 KB program RAM (instructions + data)
//   0x1000_0000                 LED debug register (bring-up test only;
//                                milestone 2 adds the real audio registers
//                                here instead of/alongside this).
//
// mem_ready timing follows the proven picosoc.v idiom: ram_ready is a
// registered pulse that fires exactly one cycle after a RAM-targeted
// request, matching cpu_ram.v's one-cycle read latency. Peripheral
// registers below are simple single-cycle writes, so their ready is
// combinational.

module cpu_bus (
    input  wire        clk,
    input  wire        resetn,

    // PicoRV32 native memory interface
    input  wire        mem_valid,
    input  wire        mem_instr,
    output wire        mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output wire [31:0] mem_rdata,

    // Peripheral: debug LED register (bring-up test only)
    output reg  [5:0]  cpu_led
);

    // ── Address decode ───────────────────────────────────────────────────
    wire ram_sel = mem_valid && (mem_addr < 32'h0000_1000);
    wire led_sel = mem_valid && (mem_addr == 32'h1000_0000);

    // ── Program RAM ──────────────────────────────────────────────────────
    wire [31:0] ram_rdata;

    cpu_ram #(.WORDS(1024)) u_ram (
        .clk  (clk),
        .wen  (ram_sel ? mem_wstrb : 4'b0),
        .addr (mem_addr[11:2]),
        .wdata(mem_wdata),
        .rdata(ram_rdata)
    );

    // One-cycle delayed ready pulse — mirrors cpu_ram.v's registered rdata.
    reg ram_ready;
    always @(posedge clk)
        ram_ready <= mem_valid && !mem_ready && ram_sel;

    // ── LED debug register ───────────────────────────────────────────────
    always @(posedge clk) begin
        if (!resetn)
            cpu_led <= 6'b0;
        else if (led_sel && mem_wstrb[0])
            cpu_led <= mem_wdata[5:0];
    end

    // ── Bus response mux ─────────────────────────────────────────────────
    assign mem_ready = ram_ready || led_sel;
    assign mem_rdata = ram_ready ? ram_rdata : 32'h0000_0000;

endmodule
