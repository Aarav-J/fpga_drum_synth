// Drum synthesizer + DDS tone
//
// UART protocol (115200 baud, single byte commands):
//   'k' (0x6B) — kick
//   's' (0x73) — snare
//   'h' (0x68) — closed hi-hat
//   'H' (0x48) — open hi-hat
//   'n' (0x6E) — cycle note up
//
// S1 — cycle note (fallback if no UART connected)
// S2 — kick       (fallback)
//
// LEDs show current note index in binary.

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

    // Decode UART commands into one-cycle trigger pulses
    wire trig_kick   = rx_valid && (rx_data == 8'h6B);  // 'k'
    wire trig_snare  = rx_valid && (rx_data == 8'h73);  // 's'
    wire trig_hihat  = rx_valid && (rx_data == 8'h68);  // 'h'
    wire trig_open   = rx_valid && (rx_data == 8'h48);  // 'H'
    wire trig_note   = rx_valid && (rx_data == 8'h6E);  // 'n'

    // ── Debounce S1 ───────────────────────────────────────────────────────
    localparam DEBOUNCE = 27_000;

    reg [14:0] db0;
    reg        s1_clean = 1'b1, s1_prev = 1'b1;

    always @(posedge clk) begin
        s1_prev <= s1_clean;
        if (btn[0] == s1_clean)
            db0 <= 0;
        else if (db0 == DEBOUNCE - 1) begin
            s1_clean <= btn[0];
            db0      <= 0;
        end else
            db0 <= db0 + 1;
    end

    wire s1_press = s1_prev & ~s1_clean;

    // ── Debounce S2 ───────────────────────────────────────────────────────
    reg [14:0] db1;
    reg        s2_clean = 1'b1, s2_prev = 1'b1;

    always @(posedge clk) begin
        s2_prev <= s2_clean;
        if (btn[1] == s2_clean)
            db1 <= 0;
        else if (db1 == DEBOUNCE - 1) begin
            s2_clean <= btn[1];
            db1      <= 0;
        end else
            db1 <= db1 + 1;
    end

    wire s2_press = s2_prev & ~s2_clean;

    // ── Note selector ─────────────────────────────────────────────────────
    reg [2:0] note;

    always @(posedge clk)
        if (s1_press || trig_note) note <= note + 1;

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

    // ── Drum voices ───────────────────────────────────────────────────────
    wire [15:0] kick_sample;
    drum_kick u_kick (
        .clk    (clk),
        .trigger(s2_press || trig_kick),
        .sample (kick_sample)
    );

    wire [15:0] snare_sample;
    drum_snare u_snare (
        .clk    (clk),
        .trigger(trig_snare),
        .lfsr   (lfsr),
        .sample (snare_sample)
    );

    wire [15:0] hihat_sample;
    drum_hihat u_hihat (
        .clk    (clk),
        .trigger(trig_hihat || trig_open),
        .open   (trig_open),
        .sample (hihat_sample),
        .lfsr   (lfsr)
    );

    // ── 4-channel mixer ───────────────────────────────────────────────────
    // Shift each channel right by 2 (divide by 4) before summing
    // to keep the total within 16-bit range.
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
    assign led = ~{3'b000, note};

endmodule
