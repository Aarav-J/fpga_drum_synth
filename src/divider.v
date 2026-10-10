
//
// Toggles `out` every N clock cycles, producing a square wave at:
//     frequency = CLK_FREQ / (2 * N)
//
// Example at 27 MHz:
//     N = 30_681  →  440 Hz  (A4)
//     N = 13_500_000  →  1 Hz   (1-second blink)
//
// Counter width is derived automatically from N via $clog2 so the
// register never wastes bits and never overflows regardless of N.

module divider #(
    parameter N = 13_500_000          // half-period in clock cycles
) (
    input  wire clk,
    output reg  out
);

    reg [$clog2(N)-1:0] counter;

    always @(posedge clk) begin
        if (counter == N - 1) begin
            counter <= 0;
            out     <= ~out;
        end else begin
            counter <= counter + 1;
        end
    end

endmodule
