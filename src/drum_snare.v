// Snare drum synthesis
//
// Two components mixed:
//   1. LFSR noise burst  — the "crack"
//   2. Sine tone ~180 Hz — the "body"
// Both share the same amplitude envelope, decaying over ~120 ms.
//
// Trigger: pulse `trigger` high for one cycle to fire.
// Noise:   pass in the running `lfsr` wire from top.v.

module drum_snare (
    input  wire        clk,
    input  wire        trigger,
    input  wire [15:0] lfsr,     // shared LFSR from top.v
    output wire [15:0] sample
);

    // ── Tone DDS ─────────────────────────────────────────────────────────
    // 180 Hz: tuning_word = (180 * 2^32) / 27_000_000 = 28_633_116
    localparam TONE_WORD = 32'd28_633_116;

    reg [31:0] phase;
    wire [15:0] sine_out;

    sine_rom u_rom (
        .clk (clk),
        .addr(phase[31:24]),
        .data(sine_out)
    );

    // ── Envelope ─────────────────────────────────────────────────────────
    // Updates every 500 cycles (~54 kHz rate).
    // Decay constant 32650/32768 ≈ 0.9964 per update → ~120 ms to silence.
    reg        active;
    reg [15:0] gain;
    reg [15:0] env_cnt;

    always @(posedge clk) begin
        if (trigger) begin
            active  <= 1;
            phase   <= 0;
            gain    <= 16'd32767;
            env_cnt <= 0;
        end else if (active) begin
            phase <= phase + TONE_WORD;

            if (env_cnt == 16'd499) begin
                env_cnt <= 0;
                gain    <= (gain * 32'd32650) >> 15;
                if (gain < 16'd10)
                    active <= 0;
            end else
                env_cnt <= env_cnt + 1;
        end
    end

    // ── Mix noise + tone, scale by envelope ──────────────────────────────
    // Noise: take raw LFSR as signed sample (reinterpret bits).
    // Tone:  sine_out from ROM.
    // Mix 60% noise + 40% tone, then scale by gain.
    wire [15:0] noise_scaled = {1'b0, lfsr[15:1]};          // half amplitude
    wire [15:0] tone_scaled  = {1'b0, sine_out[15:1]};      // half amplitude

    wire [15:0] mix = $signed(noise_scaled) + $signed(tone_scaled);

    wire [31:0] product = $signed({{1{mix[15]}}, mix}) * $signed({1'b0, gain});
    assign sample = active ? product[30:15] : 16'h0000;

endmodule
