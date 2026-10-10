// Step 5: Multiple musical notes
//
// S1 cycles through the C major scale (C4 → C5).
// LEDs show the current note index in binary on LED[2:0].
//
// Half-period formula: 27_000_000 / (2 * frequency)
//
//   Note   Freq (Hz)   Half-period
//   C4     261.63      51_603
//   D4     293.66      45_977
//   E4     329.63      40_955
//   F4     349.23      38_657
//   G4     392.00      34_439
//   A4     440.00      30_682
//   B4     493.88      27_335
//   C5     523.25      25_801

module top (
    input  wire       clk,
    input  wire [1:0] btn,   // S1 = btn[0]: cycle note
    output wire [5:0] led,
    output wire       bck,
    output wire       lrck,
    output wire       din
);

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

    reg [2:0] note;   // 0..7, wraps automatically

    always @(posedge clk)
        if (s1_press) note <= note + 1;
    

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


    wire [15:0] sample; 
    dds u_dds ( 
        .clk (clk), 
        .tuning_word(tuning_word), 
        .sample(sample)
    );
    // ── I2S transmitter ───────────────────────────────────────────────────
    wire load;

    i2s_tx #(
        .CLK_FREQ   (27_000_000),
        .SAMPLE_RATE(48_000),
        .DATA_WIDTH (16)
    ) u_i2s (
        .clk  (clk),
        .left (sample),
        .right(sample),
        .load (load),
        .bck  (bck),
        .lrck (lrck),
        .din  (din)
    );

    // ── LEDs — note index in binary ───────────────────────────────────────
    // LED0 = bit0, LED1 = bit1, LED2 = bit2 of note index
    // C4 = 000, D4 = 001, ... C5 = 111
    assign led = ~{3'b000, note};

endmodule
