// I2S transmitter (standard Philips I2S, 16-bit stereo)
//
// Signal timing (data changes on BCK falling edge, sampled on rising):
//
//  BCK:  __|¯|_|¯|_|¯| ... |¯|_|¯|_|¯| ... |¯|_
//  LRCK: ¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯|_______________|¯¯¯¯¯¯
//  DIN:   L15 L14 L13 ... L0  R15 R14 ... R0
//          ← left (LRCK=0) →  ← right (LRCK=1) →
//
// LRCK transitions at the same BCK edge as the last bit of each word.
// The MSB of the new word appears ONE BCK after the transition —
// correct standard I2S timing.
//
// Rates at 27 MHz with BCK_HALF=9:
//   BCK  = 27_000_000 / 18 = 1.500 MHz
//   LRCK = 1_500_000 / 32  = 46_875 Hz  (2.3 % off 48 kHz — fine for PCM5102A)
//
// `load` pulses for one cycle at the start of each new frame.
// The caller should have the next sample ready on `left`/`right`
// by the time `load` goes high; those values are latched into the
// shift register immediately.

module i2s_tx #(
    parameter CLK_FREQ    = 27_000_000,
    parameter SAMPLE_RATE = 48_000,
    parameter DATA_WIDTH  = 16
) (
    input  wire                  clk,
    input  wire [DATA_WIDTH-1:0] left,    // left channel sample  (two's complement)
    input  wire [DATA_WIDTH-1:0] right,   // right channel sample
    output reg                   load,    // high for 1 cycle when frame starts
    output reg                   bck,     // bit clock
    output reg                   lrck,    // word clock: 0 = left, 1 = right
    output reg                   din      // serial data, MSB first
);

    // BCK half-period in system clock cycles (rounded to nearest integer)
    // BCK target = SAMPLE_RATE * DATA_WIDTH * 2 channels = 1.536 MHz
    // BCK_HALF  = CLK_FREQ / (2 * BCK_target) = 8.789 → 9
    localparam BCK_HALF = (CLK_FREQ + SAMPLE_RATE * DATA_WIDTH * 2 - 1)
                          / (SAMPLE_RATE * DATA_WIDTH * 4);   // = 9

    reg [$clog2(BCK_HALF)-1:0]  div;
    reg [4:0]                    bit_cnt;              // 0 .. 2*DATA_WIDTH-1
    reg [2*DATA_WIDTH-1:0]       shift;

    always @(posedge clk) begin
        load <= 0;

        if (div == BCK_HALF - 1) begin
            div <= 0;
            bck <= ~bck;

            // Act on the falling edge (bck is still 1 here due to NBA)
            if (bck) begin

                // Shift out the MSB
                din   <= shift[2*DATA_WIDTH-1];
                shift <= {shift[2*DATA_WIDTH-2:0], 1'b0};

                if (bit_cnt == 2*DATA_WIDTH - 1) begin
                    // End of frame — load next sample, start left channel
                    bit_cnt <= 0;
                    lrck    <= 0;
                    shift   <= {left, right};
                    load    <= 1;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                    // LRCK goes high at the same edge as left[0],
                    // so right[15] (MSB) appears one BCK later — standard I2S
                    if (bit_cnt == DATA_WIDTH - 1)
                        lrck <= 1;
                end

            end
        end else
            div <= div + 1;
    end

endmodule
