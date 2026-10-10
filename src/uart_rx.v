// UART receiver
//
// Samples a standard 8N1 UART frame (no parity, 1 stop bit) and
// asserts `valid` for exactly one clock cycle when a byte is ready.
//
// 8N1 frame on the wire:
//   ____          _______________________________          ____
//       |________|  b0  b1  b2  b3  b4  b5  b6  b7  |
//        start bit  <------ 8 data bits (LSB first) ----->  stop
//
// Sampling strategy:
//   - Detect falling edge on rx (start bit).
//   - Wait HALF_BIT cycles to land in the centre of the start bit.
//   - Sample every CLKS_PER_BIT cycles for 8 data bits.
//   - Verify stop bit; assert valid if it is high (clean frame).
//
// Baud rate accuracy @ 27 MHz / 115200:
//   CLKS_PER_BIT = 234   →  actual baud = 27_000_000 / 234 = 115_385
//   error = 0.16 %  — well inside the ±2 % UART tolerance

module uart_rx #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115_200
) (
    input  wire       clk,
    input  wire       rx,    // serial line, idle = 1
    output reg  [7:0] data,  // received byte, held until next byte arrives
    output reg        valid  // high for ONE clock cycle when data is ready
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // 234
    localparam HALF_BIT     = CLKS_PER_BIT / 2;       // 117

    // State machine
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]                      state = IDLE;
    reg [$clog2(CLKS_PER_BIT)-1:0] count;   // cycle counter within a bit period
    reg [2:0]                      bit_idx; // which data bit we are sampling (0-7)
    reg [7:0]                      rx_shift; // shift register, filled LSB first

    always @(posedge clk) begin
        valid <= 0;  // default: not valid; overridden in STOP when frame is good

        case (state)

            // Wait for the line to fall (start bit).
            IDLE: begin
                if (rx == 0) begin
                    count <= 0;
                    state <= START;
                end
            end

            // Sit out half a bit period to land in the centre of the start bit,
            // then arm the data sampler.
            START: begin
                if (count == HALF_BIT - 1) begin
                    count   <= 0;
                    bit_idx <= 0;
                    state   <= DATA;
                end else
                    count <= count + 1;
            end

            // Sample rx at the centre of each of the 8 data bits.
            // Shift right: new bit enters at [7], previously received bits
            // move down. After 8 shifts rx_shift = {b7,b6,b5,b4,b3,b2,b1,b0}.
            // This avoids a variable-indexed write, which Yosys turns into
            // $buf cells the Gowin nextpnr backend cannot place.
            DATA: begin
                if (count == CLKS_PER_BIT - 1) begin
                    rx_shift <= {rx, rx_shift[7:1]};  // shift right, LSB-first wire
                    count    <= 0;
                    if (bit_idx == 7)
                        state <= STOP;
                    else
                        bit_idx <= bit_idx + 1;
                end else
                    count <= count + 1;
            end

            // Wait one more bit period for the stop bit.
            // If rx is high the frame is valid; latch the byte and pulse valid.
            STOP: begin
                if (count == CLKS_PER_BIT - 1) begin
                    if (rx == 1) begin
                        data  <= rx_shift;
                        valid <= 1;
                    end
                    // rx==0 here means framing error — silently drop and resync
                    state <= IDLE;
                end else
                    count <= count + 1;
            end

        endcase
    end

endmodule
