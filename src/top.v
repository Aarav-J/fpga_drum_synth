// FPGA Drum Machine — HardBeat
//
// UART command protocol (115200 baud):
//   'P'       — play / pause toggle
//   'C'       — clear all steps
//   'n'       — cycle note up
//   'B' <idx> — set BPM (idx 0-7: 60/70/80/100/120/140/160/180)
//   'W' <step> <mask> — write step (step 0-15, mask = kick|snare|hihat|open)
//
// Manual triggers (bypass sequencer):
//   'k' — kick   's' — snare   'h' — hi-hat   'H' — open hi-hat
//
// Buttons:
//   S1 — cycle note
//   S2 — play / pause
//
// LEDs:
//   [2:0] — current sequencer step (0-15, lower 3 bits)
//   [5:3] — current note index

module top (
    input  wire       clk,
    input  wire [1:0] btn,
    output wire [5:0] led,
    output wire       bck,
    output wire       lrck,
    output wire       din,
    input  wire       uart_rx
);

    // ── LFSR — shared noise source ────────────────────────────────────────
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk)
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};


    // ── UART receiver ─────────────────────────────────────────────────────
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(
        .CLK_FREQ (27_000_000),
        .BAUD_RATE(115_200)
    ) u_rx (
        .clk  (clk),
        .rx   (uart_rx),
        .data (rx_data),
        .valid(rx_valid)
    );

    // ── UART command parser ───────────────────────────────────────────────
    // State machine: IDLE → waiting for command byte
    //                WAIT_BPM  → next byte is BPM index
    //                WAIT_STEP → next byte is step number
    //                WAIT_MASK → next byte is voice mask
    localparam CMD_IDLE      = 2'd0;
    localparam CMD_WAIT_BPM  = 2'd1;
    localparam CMD_WAIT_STEP = 2'd2;
    localparam CMD_WAIT_MASK = 2'd3;

    wire s2_press;
    reg [1:0]  cmd_state = CMD_IDLE;
    reg [3:0]  cmd_step;
    reg [2:0]  bpm_idx = 3'd4;
    reg        play = 1'b0;
    reg        seq_clear;
    reg        seq_wr_en;
    reg [3:0]  seq_wr_step;
    reg [3:0]  seq_wr_mask;

    // Manual one-shot triggers (bypass sequencer)
    reg man_kick, man_snare, man_hihat, man_open;

    always @(posedge clk) begin
        // Default: clear one-cycle signals
        seq_clear  <= 0;
        seq_wr_en  <= 0;
        man_kick   <= 0;
        man_snare  <= 0;
        man_hihat  <= 0;
        man_open   <= 0;
        if (s2_press) play <= ~play;

        if (rx_valid) begin
            case (cmd_state)
                CMD_IDLE: begin
                    case (rx_data)
                        8'h50: play      <= ~play;       // 'P' play/pause
                        8'h43: seq_clear <= 1;           // 'C' clear
                        8'h6E: /* 'n' handled below */;
                        8'h42: cmd_state <= CMD_WAIT_BPM;  // 'B'
                        8'h57: cmd_state <= CMD_WAIT_STEP; // 'W'
                        8'h6B: man_kick  <= 1;           // 'k'
                        8'h73: man_snare <= 1;           // 's'
                        8'h68: man_hihat <= 1;           // 'h'
                        8'h48: man_open  <= 1;           // 'H'
                        default:;
                    endcase
                end
                CMD_WAIT_BPM: begin
                    bpm_idx  <= rx_data[2:0];
                    cmd_state <= CMD_IDLE;
                end
                CMD_WAIT_STEP: begin
                    cmd_step  <= rx_data[3:0];
                    cmd_state <= CMD_WAIT_MASK;
                end
                CMD_WAIT_MASK: begin
                    seq_wr_en   <= 1;
                    seq_wr_step <= cmd_step;
                    seq_wr_mask <= rx_data[3:0];
                    cmd_state   <= CMD_IDLE;
                end
            endcase
        end
    end

    // ── Debounce S1 ───────────────────────────────────────────────────────
    localparam DEBOUNCE = 27_000;

    reg [14:0] db0;
    reg        s1_clean = 1'b1, s1_prev = 1'b1;

    always @(posedge clk) begin
        s1_prev <= s1_clean;
        if (btn[0] == s1_clean) db0 <= 0;
        else if (db0 == DEBOUNCE - 1) begin
            s1_clean <= btn[0]; db0 <= 0;
        end else db0 <= db0 + 1;
    end

    wire s1_press = s1_prev & ~s1_clean;

    // ── Debounce S2 ───────────────────────────────────────────────────────
    reg [14:0] db1;
    reg        s2_clean = 1'b1, s2_prev = 1'b1;

    always @(posedge clk) begin
        s2_prev <= s2_clean;
        if (btn[1] == s2_clean) db1 <= 0;
        else if (db1 == DEBOUNCE - 1) begin
            s2_clean <= btn[1]; db1 <= 0;
        end else db1 <= db1 + 1;
    end

    assign s2_press = s2_prev & ~s2_clean;


    // ── Note selector ─────────────────────────────────────────────────────
    reg [2:0] note;
    always @(posedge clk)
        if (s1_press || (rx_valid && rx_data == 8'h6E))
            note <= note + 1;

    reg [31:0] tuning_word;
    always @(*) begin
        case (note)
            3'd0: tuning_word = 32'd41_648_698;  // C4
            3'd1: tuning_word = 32'd46_762_507;  // D4
            3'd2: tuning_word = 32'd52_496_838;  // E4
            3'd3: tuning_word = 32'd55_620_560;  // F4
            3'd4: tuning_word = 32'd62_393_524;  // G4
            3'd5: tuning_word = 32'd70_041_785;  // A4
            3'd6: tuning_word = 32'd78_631_077;  // B4
            3'd7: tuning_word = 32'd83_297_396;  // C5
        endcase
    end

    // ── DDS tone ──────────────────────────────────────────────────────────
    wire [15:0] tone_sample;

    dds u_dds (
        .clk        (clk),
        .tuning_word(tuning_word),
        .sample     (tone_sample)
    );

    // ── Sequencer ─────────────────────────────────────────────────────────
    wire        seq_trig_kick, seq_trig_snare, seq_trig_hihat, seq_trig_open;
    wire [3:0]  step_out;

    sequencer u_seq (
        .clk      (clk),
        .play     (play),
        .bpm_idx  (bpm_idx),
        .wr_en    (seq_wr_en),
        .wr_step  (seq_wr_step),
        .wr_mask  (seq_wr_mask),
        .clear    (seq_clear),
        .step_out (step_out),
        .trig_kick (seq_trig_kick),
        .trig_snare(seq_trig_snare),
        .trig_hihat(seq_trig_hihat),
        .trig_open (seq_trig_open)
    );

    // ── Drum voices ───────────────────────────────────────────────────────
    wire [15:0] kick_sample;
    drum_kick u_kick (
        .clk    (clk),
        .trigger(seq_trig_kick || man_kick),
        .sample (kick_sample)
    );

    wire [15:0] snare_sample;
    drum_snare u_snare (
        .clk    (clk),
        .trigger(seq_trig_snare || man_snare),
        .lfsr   (lfsr),
        .sample (snare_sample)
    );

    wire [15:0] hihat_sample;
    drum_hihat u_hihat (
        .clk    (clk),
        .trigger(seq_trig_hihat || man_hihat || seq_trig_open || man_open),
        .open   (seq_trig_open  || man_open),
        .lfsr   (lfsr),
        .sample (hihat_sample)
    );

    // ── 4-channel mixer ───────────────────────────────────────────────────
    wire [15:0] mixed =
        {{2{tone_sample[15]}},  tone_sample[15:2]}  +
        {{2{kick_sample[15]}},  kick_sample[15:2]}  +
        {{2{snare_sample[15]}}, snare_sample[15:2]} +
        {{2{hihat_sample[15]}}, hihat_sample[15:2]};

    // ── I2S transmitter ───────────────────────────────────────────────────
    wire load;

    i2s_tx #(
        .CLK_FREQ   (27_000_000),
        .SAMPLE_RATE(48_000),
        .DATA_WIDTH (16)
    ) u_i2s (
        .clk  (clk),
        .left (mixed),
        .right(mixed),
        .load (load),
        .bck  (bck),
        .lrck (lrck),
        .din  (din)
    );

    // ── LEDs ──────────────────────────────────────────────────────────────
    // [2:0] = lower 3 bits of current step (blinks through 0-7 twice per bar)
    // [5:3] = current note index
    assign led = ~{note, step_out[2:0]};

endmodule
