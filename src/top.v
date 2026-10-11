// FPGA Drum Machine — HardBeat
//
// UART command protocol (115200 baud):
//   'P'       — play / pause toggle
//   'p' / 'q' — explicitly play / pause
//   'C'       — clear all steps
//   'n'       — cycle note up
//   'N' <idx> — select note (idx 0-7: C4/D4/E4/F4/G4/A4/B4/C5)
//   'T' <on>  — DDS envelope gate off/on (0/1, initially on)
//   'V' <gain> — master amplitude (0-128: 0=mute, 64=100%, 128=200%)
//   'B' <idx> — set BPM (idx 0-7: 60/70/80/100/120/140/160/180)
//   'W' <step> <mask> — write step (step 0-15, mask = kick|snare|hihat|open)
// Payloads are raw bytes, not ASCII digits; invalid N/T/V payloads are ignored.
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
//           NOTE: [0] is temporarily overridden by the PicoRV32 bring-up
//           test (cpu_led[0]) — see the LED section below.
//   [5:3] — current note index

module top (
    input  wire       clk,
    input  wire [1:0] btn,
    output wire [5:0] led,
    output wire       bck,
    output wire       lrck,
    output wire       din,
    input  wire       uart_rx,
    // HDMI differential pairs (video only, DVI-compatible)
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n
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
    //                WAIT_NOTE → next byte is note index (0-7)
    //                WAIT_TONE → next byte is DDS envelope gate (0/1)
    //                WAIT_VOLUME → next byte is master gain (0-128)
    localparam CMD_IDLE      = 3'd0;
    localparam CMD_WAIT_BPM  = 3'd1;
    localparam CMD_WAIT_STEP = 3'd2;
    localparam CMD_WAIT_MASK = 3'd3;
    localparam CMD_WAIT_NOTE = 3'd4;
    localparam CMD_WAIT_TONE = 3'd5;
    localparam CMD_WAIT_VOLUME = 3'd6;

    wire s2_press;
    reg [2:0]  cmd_state = CMD_IDLE;
    reg [3:0]  cmd_step;
    reg [2:0]  bpm_idx = 3'd4;
    reg        play = 1'b0;
    reg        tone_enabled = 1'b1;
    reg [7:0]  master_gain = 8'd128;
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
                        8'h70: play      <= 1'b1;        // 'p' play
                        8'h71: play      <= 1'b0;        // 'q' pause
                        8'h43: seq_clear <= 1;           // 'C' clear
                        8'h6E: /* 'n' handled below */;
                        8'h42: cmd_state <= CMD_WAIT_BPM;  // 'B'
                        8'h57: cmd_state <= CMD_WAIT_STEP; // 'W'
                        8'h4E: cmd_state <= CMD_WAIT_NOTE; // 'N'
                        8'h54: cmd_state <= CMD_WAIT_TONE; // 'T'
                        8'h56: cmd_state <= CMD_WAIT_VOLUME; // 'V'
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
                CMD_WAIT_NOTE: begin
                    // The note selector below owns the note register.
                    cmd_state <= CMD_IDLE;
                end
                CMD_WAIT_TONE: begin
                    if (rx_data <= 8'd1)
                        tone_enabled <= rx_data[0];
                    cmd_state <= CMD_IDLE;
                end
                CMD_WAIT_VOLUME: begin
                    if (rx_data <= 8'd128)
                        master_gain <= rx_data;
                    cmd_state <= CMD_IDLE;
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
    wire select_note = rx_valid && cmd_state == CMD_WAIT_NOTE && rx_data <= 8'd7;
    always @(posedge clk)
        if (select_note)
            note <= rx_data[2:0];
        else if (s1_press || (rx_valid && cmd_state == CMD_IDLE && rx_data == 8'h6E))
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
    wire [15:0] envelope_sample;
    wire load;

    dds u_dds (
        .clk        (clk),
        .tuning_word(tuning_word),
        .sample     (tone_sample)
    );

    synth_envelope u_envelope (
        .clk        (clk),
        .sample_tick(load),
        .gate       (tone_enabled),
        .sample_in  (tone_sample),
        .sample_out (envelope_sample)
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
    // Sum at full precision, then apply unsigned gain with a signed product.
    // Gain 64 quarters the sum (100%); gain 128 halves it (200%, initial).
    // Saturate peaks rather than wrapping in 16-bit arithmetic.
    wire signed [17:0] mix_sum =
        $signed({{2{envelope_sample[15]}}, envelope_sample}) +
        $signed({{2{kick_sample[15]}}, kick_sample}) +
        $signed({{2{snare_sample[15]}}, snare_sample}) +
        $signed({{2{hihat_sample[15]}}, hihat_sample});
    wire signed [26:0] mix_product = mix_sum * $signed({1'b0, master_gain});
    wire signed [26:0] mix_scaled = mix_product >>> 8;
    wire [15:0] mixed = (mix_scaled > 27'sd32767) ? 16'h7fff :
                        (mix_scaled < -27'sd32768) ? 16'h8000 :
                        mix_scaled[15:0];

    // ── I2S transmitter ───────────────────────────────────────────────────
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

    // ── PicoRV32 CPU — bring-up milestone 1 ─────────────────────────────────
    // Boots from 4 KB program RAM (cpu_ram.v) loaded from firmware/firmware.hex
    // at synthesis time. Only a single LED debug register is wired up so far
    // (see cpu_bus.v) — this exists purely to prove the toolchain, memory
    // map, and CPU execution all work end-to-end before milestone 2 wires
    // the CPU into the note/sequencer control path for song playback.
    //
    // Runs on the same 27 MHz clock as everything else — no separate clock
    // domain, no synchronizers needed for this core.
    // PicoRV32 needs resetn actually pulsed low at least once — its reset
    // logic (cpu_state <= cpu_state_fetch, reg_pc <= PROGADDR_RESET) only
    // runs inside `if (!resetn)`. Same pattern as dvi_tx.v's rst_cnt: hold
    // low for a few clock cycles after configuration, then release.
    reg  [3:0]  cpu_rst_cnt = 4'd0;
    wire        cpu_resetn = cpu_rst_cnt[3];
    always @(posedge clk)
        if (!cpu_rst_cnt[3])
            cpu_rst_cnt <= cpu_rst_cnt + 1'b1;
    wire        cpu_mem_valid, cpu_mem_instr, cpu_mem_ready;
    wire [31:0] cpu_mem_addr, cpu_mem_wdata, cpu_mem_rdata;
    wire [3:0]  cpu_mem_wstrb;
    wire [5:0]  cpu_led;

    picorv32 #(
        .ENABLE_MUL     (0),
        .ENABLE_DIV     (0),
        .ENABLE_IRQ     (0),
        .ENABLE_IRQ_QREGS(0),
        .BARREL_SHIFTER (0),
        .PROGADDR_RESET (32'h0000_0000),
        .STACKADDR      (32'h0000_1000)
    ) u_cpu (
        .clk      (clk),
        .resetn   (cpu_resetn),
        .trap     (),
        .mem_valid(cpu_mem_valid),
        .mem_instr(cpu_mem_instr),
        .mem_ready(cpu_mem_ready),
        .mem_addr (cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wstrb(cpu_mem_wstrb),
        .mem_rdata(cpu_mem_rdata),
        .mem_la_read (),
        .mem_la_write(),
        .mem_la_addr (),
        .mem_la_wdata(),
        .mem_la_wstrb(),
        .pcpi_valid(),
        .pcpi_insn (),
        .pcpi_rs1  (),
        .pcpi_rs2  (),
        .pcpi_wr   (1'b0),
        .pcpi_rd   (32'b0),
        .pcpi_wait (1'b0),
        .pcpi_ready(1'b0),
        .irq       (32'b0),
        .eoi       (),
        .trace_valid(),
        .trace_data ()
    );

    cpu_bus u_cpu_bus (
        .clk      (clk),
        .resetn   (cpu_resetn),
        .mem_valid(cpu_mem_valid),
        .mem_instr(cpu_mem_instr),
        .mem_ready(cpu_mem_ready),
        .mem_addr (cpu_mem_addr),
        .mem_wdata(cpu_mem_wdata),
        .mem_wstrb(cpu_mem_wstrb),
        .mem_rdata(cpu_mem_rdata),
        .cpu_led  (cpu_led)
    );

    // ── LEDs ──────────────────────────────────────────────────────────────
    // [2:0] = lower 3 bits of current step (blinks through 0-7 twice per bar)
    // [5:3] = current note index
    //
    // TEMPORARY bring-up override: ALL 6 LEDs show cpu_led directly, so
    // there's no ambiguity with the sequencer's step/note LEDs while
    // debugging the CPU. Revert to `~{note, step_out[2:0]}` once milestone 1
    // is confirmed working.
    assign led = ~cpu_led;

    // ── HDMI sequencer display ────────────────────────────────────────────
    // Transfer sequencer state into the pixel clock domain with 2-FF
    // synchronizers.  Only the step index and play flag need to cross.
    wire        clk_pix, vid_reset;
    wire [9:0]  px, py;
    wire        vid_frame;

    // --- 2-FF sync: step_out (4 bits) and play into pixel domain ----
    reg [3:0] sync1_step, sync2_step;
    reg       sync1_play, sync2_play;
    always @(posedge clk_pix) begin
        sync1_step <= step_out;  sync2_step <= sync1_step;
        sync1_play <= play;      sync2_play <= sync1_play;
    end

    // --- 2-FF sync: master_gain into pixel domain ---
    reg [7:0] sync1_gain, sync2_gain;
    always @(posedge clk_pix) begin
        sync1_gain <= master_gain;
        sync2_gain <= sync1_gain;
    end

    // --- 2-FF sync: tone_enabled (used to show note active) ----
    reg sync1_tone, sync2_tone;
    always @(posedge clk_pix) begin
        sync1_tone <= tone_enabled; sync2_tone <= sync1_tone;
    end

    // --- pixel-domain pattern shadow: resample on frame pulse ----------
    // Shift the 16×4 pattern into a shift register from the 27 MHz domain.
    // Instead of a full multi-bit synchronizer for 64 bits we capture the
    // entire pattern word at the start of each frame (frame = blanking,
    // 27 MHz and pixel clocks are both running, so occasional mis-captures
    // produce at most one frame of glitch — acceptable for a display).
    reg [63:0] pat_sr_27;  // packed pattern in 27 MHz domain
    integer si;
    always @(posedge clk) begin
        for (si = 0; si < 16; si = si + 1)
            pat_sr_27[si*4 +: 4] <= u_seq.pattern[si];
    end
    reg [63:0] pat_pix = 64'd0;
    reg        frame_prev = 1'b0;
    always @(posedge clk_pix) begin
        frame_prev <= vid_frame;
        if (vid_frame && !frame_prev)
            pat_pix <= pat_sr_27;
    end

    // --- grid drawing ----------------------------------------------------
    // Display: 16-column × 4-row grid of drum step cells.
    // Cell size: 36×36 px.  Grid starts at (80, 80).
    // Below the grid: a row of 16 step-indicator dots (current step).
    // Top-left corner label region: unused (reserved for future text).
    //
    // Colours (8-bit per channel packed into {r,g,b}):
    //   Background          #1a1a2e   dark navy
    //   Grid line           #2a2a4e   lighter navy
    //   Cell off            #0d3b5e   dark blue
    //   Cell on             #4eb5ff   bright blue
    //   Current step        #ffcc00   amber highlight
    //   Current step + on   #ff8800   orange (active + current)
    //   Play indicator      #22cc66   green when playing

    localparam GX   = 80;   // grid left edge
    localparam GY   = 80;   // grid top edge
    localparam CW   = 36;   // cell width (pixels)
    localparam CH   = 36;   // cell height
    localparam COLS = 16;
    localparam ROWS = 4;
    localparam GAP  = 2;    // gap between cells

    // Derived dimensions — must be parameters or localparam to avoid width
    // mismatch with 10-bit pixel coords.
    localparam GW = COLS * (CW + GAP);   // grid width  = 608 px
    localparam GH = ROWS * (CH + GAP);   // grid height = 152 px

    wire in_grid = (px >= GX) && (px < GX + GW) && (py >= GY) && (py < GY + GH);

    wire [3:0] cell_col = (px - GX) / (CW + GAP);
    wire [1:0] cell_row = (py - GY) / (CH + GAP);
    wire [4:0] cx       = (px - GX) % (CW + GAP);  // x within cell+gap slot
    wire [4:0] cy       = (py - GY) % (CH + GAP);  // y within cell+gap slot
    wire       in_cell  = in_grid && (cx < CW) && (cy < CH);
    wire       cell_bit = pat_pix[{cell_col, cell_row}];  // bit for this cell
    wire       is_cur   = (cell_col == sync2_step);

    // Step-indicator bar: 16 small dots 8×8 px, centred below the grid.
    localparam IY = GY + GH + 20;  // indicator y start
    localparam IH = 8;
    localparam IW = 8;
    localparam IX = GX + (GW - COLS * (IW + 2)) / 2;  // centred
    wire in_indicator = (py >= IY) && (py < IY + IH) &&
                        (px >= IX) && (px < IX + COLS * (IW + 2));
    wire [3:0] ind_col = (px - IX) / (IW + 2);
    wire       in_dot  = in_indicator && ((px - IX) % (IW + 2) < IW);
    wire       dot_cur = (ind_col == sync2_step);

    // Play indicator: small rectangle top-left corner
    wire in_play = (px >= 20) && (px < 52) && (py >= 20) && (py < 36);

    // BPM index label: shown as 8 horizontal bars (crude progress bar)
    wire in_bpm = (px >= 20) && (px < 20 + bpm_idx * 8) && (py >= 44) && (py < 52);
    // Vertical volume bar: takes up 10 pixels with 2-pixel gap, 0-128 gain
    // mapped to 0-10 pixels

    wire [14:0] bar_product = {7'b0, sync2_gain} * 15'd60; // full 15-bit product
    wire [6:0]  bar_fill    = bar_product >> 7;             // 0-60 px
    wire in_volume_bar = (px >= 20) && (px < 32) &&
                         (py >= 270) && (py < 330) &&
                         (py >= (330 - bar_fill));
    reg [7:0] vr, vg, vb;
    always @(posedge clk_pix) begin
        vr <= 8'h1a; vg <= 8'h1a; vb <= 8'h2e;  // default background
        if (in_cell) begin
            if (cell_bit && is_cur) begin          // on + current step
                vr <= 8'hff; vg <= 8'h88; vb <= 8'h00;
            end else if (is_cur) begin             // current step, not on
                vr <= 8'hff; vg <= 8'hcc; vb <= 8'h00;
            end else if (cell_bit) begin           // on, not current
                vr <= 8'h4e; vg <= 8'hb5; vb <= 8'hff;
            end else begin                         // off
                vr <= 8'h0d; vg <= 8'h3b; vb <= 8'h5e;
            end
        end
        if (in_dot) begin
            if (dot_cur)
                begin vr <= 8'hff; vg <= 8'hcc; vb <= 8'h00; end
            else
                begin vr <= 8'h2a; vg <= 8'h2a; vb <= 8'h4e; end
        end
        if (in_play && sync2_play)
            begin vr <= 8'h22; vg <= 8'hcc; vb <= 8'h66; end
        if (in_bpm)
            begin vr <= 8'h66; vg <= 8'haa; vb <= 8'hff; end
        if (in_volume_bar)
            begin vr <= 8'hff; vg <= 8'hff; vb <= 8'hff; end
    end


    dvi_tx #(.PIPE(1)) u_dvi (
        .clk_27    (clk),
        .clk_pix   (clk_pix),
        .reset     (vid_reset),
        .frame     (vid_frame),
        .x         (px),
        .y         (py),
        .rgb       ({vr, vg, vb}),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_d_p  (tmds_d_p),
        .tmds_d_n  (tmds_d_n)
    );

endmodule
