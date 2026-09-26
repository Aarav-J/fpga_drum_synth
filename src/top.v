// Step 1: LED blink
// Blinks LED0 at 1 Hz to verify the toolchain end-to-end.
//
// Clock:   27 MHz (pin 52)
// LED[5:0]: active-low (pin driven 0 = LED on)
//
// 1 Hz blink: half-period = 27_000_000 / 2 = 13_500_000 cycles
// Counter width: ceil(log2(13_500_000)) = 24 bits

module top (
    input  wire       clk,      // 27 MHz
    output wire [5:0] led       // active-low, 6 LEDs
);
    reg [5:0] led_state; 
    reg [23:0] counter;
    reg        state;           // 0 → LED off, 1 → LED on

    always @(posedge clk) begin
        if (counter == 24'd13_499_999) begin
            counter <= 24'd0;
            led_state <= led_state + 6'd1; // Increment LED state
        end else begin
            counter <= counter + 24'd1;
        end
    end

    // LED[0] blinks; LED[1:5] held off.
    // Invert at the pin boundary — active-low hardware, active-high logic.
    assign led = led_state ^ 6'b111111; // Invert for active-low LEDs

endmodule
