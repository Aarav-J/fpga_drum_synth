// 16-step drum sequencer
//
// Pattern RAM: 16 entries x 4 bits
//   bit 0 = kick
//   bit 1 = snare
//   bit 2 = closed hi-hat
//   bit 3 = open hi-hat
//
// BPM lookup (send index 0-7 over UART with 'B' command):
//   0 = 60 BPM    4 = 120 BPM
//   1 = 70 BPM    5 = 140 BPM
//   2 = 80 BPM    6 = 160 BPM
//   3 = 100 BPM   7 = 180 BPM
//
// Write interface: assert wr_en for one cycle with wr_step + wr_mask.
// Play/pause:      toggle play input.

module sequencer (
    input  wire        clk,
    input  wire        play,        // 1 = running, 0 = paused
    input  wire [2:0]  bpm_idx,     // selects BPM from lookup table
    input  wire        wr_en,       // write enable — pulse for one cycle
    input  wire [3:0]  wr_step,     // which step to write (0-15)
    input  wire [3:0]  wr_mask,     // voice bitmask to write
    input  wire        clear,       // pulse: zero all steps
    output reg  [3:0]  step_out,    // current step index (for LED display)
    output reg         trig_kick,
    output reg         trig_snare,
    output reg         trig_hihat,
    output reg         trig_open
);

    // ── Pattern RAM ───────────────────────────────────────────────────────
    reg [3:0] pattern [0:15];
    integer i;

    always @(posedge clk) begin
        if (clear) begin
            for (i = 0; i < 16; i = i + 1)
                pattern[i] <= 4'b0000;
        end else if (wr_en) begin
            pattern[wr_step] <= wr_mask;
        end
    end

    // ── BPM counter lookup ────────────────────────────────────────────────
    // Four sixteenth-note steps per quarter-note beat.
    // cycles_per_step = (27_000_000 * 60) / (BPM * 4)
    reg [31:0] cycles_per_step;
    always @(*) begin
        case (bpm_idx)
            3'd0: cycles_per_step = 32'd6_750_000; //  60 BPM
            3'd1: cycles_per_step = 32'd5_785_714; //  70 BPM
            3'd2: cycles_per_step = 32'd5_062_500; //  80 BPM
            3'd3: cycles_per_step = 32'd4_050_000; // 100 BPM
            3'd4: cycles_per_step = 32'd3_375_000; // 120 BPM
            3'd5: cycles_per_step = 32'd2_892_857; // 140 BPM
            3'd6: cycles_per_step = 32'd2_531_250; // 160 BPM
            3'd7: cycles_per_step = 32'd2_250_000; // 180 BPM
        endcase
    end

    // ── Step clock ────────────────────────────────────────────────────────
    reg [31:0] clk_cnt;
    reg [3:0]  step_idx;

    wire step_advance = play && (clk_cnt == cycles_per_step - 1);

    always @(posedge clk) begin
        if (!play) begin
            clk_cnt  <= 0;
            step_idx <= 0;
        end else if (step_advance) begin
            clk_cnt  <= 0;
            step_idx <= step_idx + 1;  // wraps 15→0 automatically
        end else begin
            clk_cnt <= clk_cnt + 1;
        end
    end

    // ── Fire triggers ─────────────────────────────────────────────────────
    // Triggers are high for exactly one cycle when the step advances.
    always @(posedge clk) begin
        trig_kick  <= step_advance && pattern[step_idx][0];
        trig_snare <= step_advance && pattern[step_idx][1];
        trig_hihat <= step_advance && pattern[step_idx][2] && !pattern[step_idx][3];
        trig_open  <= step_advance && pattern[step_idx][3];
        step_out   <= step_idx;
    end

endmodule
