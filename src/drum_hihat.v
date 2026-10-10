// Hi-hat synthesis
//
// Pure noise from LFSR with a very short envelope.
// `open` parameter selects closed (~25 ms) or open (~250 ms) decay.
//
// Trigger: pulse `trigger` high for one cycle.
// Noise:   pass in the running `lfsr` wire from top.v.

module drum_hihat (
    input  wire        clk,
    input  wire        trigger,
    input  wire        open,     // 0 = closed hi-hat, 1 = open hi-hat
    input  wire [15:0] lfsr,
    output wire [15:0] sample
);

    // ── Envelope ─────────────────────────────────────────────────────────
    // Closed: decay constant 32200/32768 ≈ 0.9827 → ~25 ms
    // Open:   decay constant 32740/32768 ≈ 0.9992 → ~250 ms
    // Updates every 500 cycles.
    reg        active;
    reg [15:0] gain;
    reg [15:0] env_cnt;

    always @(posedge clk) begin
        if (trigger) begin
            active  <= 1;
            gain    <= 16'd32767;
            env_cnt <= 0;
        end else if (active) begin
            if (env_cnt == 16'd499) begin
                env_cnt <= 0;
                gain    <= open
                           ? (gain * 32'd32740) >> 15   // open — slow decay
                           : (gain * 32'd32200) >> 15;  // closed — fast decay
                if (gain < 16'd10)
                    active <= 0;
            end else
                env_cnt <= env_cnt + 1;
        end
    end

    // ── Output — raw LFSR noise scaled by envelope ────────────────────────
    wire [31:0] product = $signed({{1{lfsr[15]}}, lfsr}) * $signed({1'b0, gain});
    assign sample = active ? product[30:15] : 16'h0000;

endmodule
