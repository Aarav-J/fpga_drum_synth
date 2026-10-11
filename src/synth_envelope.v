// Sample-rate ADSR for the DDS tone, clocked by the 46,875 Hz I2S load pulse.
// Keep eight fractional bits below the Q1.15 gain to preserve the release tail.
module synth_envelope (
    input  wire        clk,
    input  wire        sample_tick,
    input  wire        gate,
    input  wire [15:0] sample_in,
    output wire [15:0] sample_out
);
    localparam [22:0] PEAK = 23'd32767 << 8;
    localparam [22:0] SUSTAIN = PEAK >> 1;
    // Widen the rounding additions: PEAK + 468 exceeds 23 bits.
    localparam [22:0] ATTACK_STEP = (PEAK + 32'd468) / 32'd469;
    localparam [22:0] DECAY_STEP = (PEAK - SUSTAIN + 32'd3749) / 32'd3750;

    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] ATTACK = 3'd1;
    localparam [2:0] DECAY = 3'd2;
    localparam [2:0] HOLD = 3'd3;
    localparam [2:0] RELEASE = 3'd4;

    reg [22:0] envelope = 23'd0;
    reg [2:0] state = IDLE;
    reg gate_previous = 1'b0;

    wire [22:0] release_step = (envelope >> 10) == 23'd0
                              ? 23'd1 : (envelope >> 10);

    always @(posedge clk) begin
        gate_previous <= gate;
        // Observe every system clock, including off/on edges between samples.
        // Changing stage preserves the current level, even during a release.
        if (gate != gate_previous) begin
            if (gate)
                state <= ATTACK;
            else
                state <= RELEASE;
        end else if (sample_tick) begin
            case (state)
                IDLE: envelope <= 23'd0;
                ATTACK: begin
                    if (envelope >= PEAK - ATTACK_STEP) begin
                        envelope <= PEAK;
                        state <= DECAY;
                    end else
                        envelope <= envelope + ATTACK_STEP;
                end
                DECAY: begin
                    if (envelope <= SUSTAIN + DECAY_STEP) begin
                        envelope <= SUSTAIN;
                        state <= HOLD;
                    end else
                        envelope <= envelope - DECAY_STEP;
                end
                HOLD: envelope <= SUSTAIN;
                RELEASE: begin
                    // Multiplication by 1023/1024 without a multiplier.
                    // Silence below one Q1.15 LSB; min step prevents stalling.
                    if (envelope < 23'd256) begin
                        envelope <= 23'd0;
                        state <= IDLE;
                    end else
                        envelope <= envelope - release_step;
                end
                default: begin
                    envelope <= 23'd0;
                    state <= IDLE;
                end
            endcase
        end
    end

    // Positive 17-bit gain times signed PCM requires all 33 product bits.
    wire signed [15:0] signed_sample = $signed(sample_in);
    wire signed [16:0] gain = $signed({2'b00, envelope[22:8]});
    wire signed [32:0] product = signed_sample * gain;
    wire signed [32:0] scaled_sample = product >>> 15;
    assign sample_out = scaled_sample[15:0];
endmodule
