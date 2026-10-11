// DVI-compatible HDMI transmitter for Tang Nano 9K — 640×480 @ 60 Hz.
//
// Clock chain (verified against stephenkingston/tang-nano-9k commit 4a32547c):
//   27 MHz board clock  →  rPLL (IDIV_SEL=2, FBDIV_SEL=13, ODIV_SEL=4)
//   → clk_x5 = 126 MHz serial clock
//   → CLKDIV #(.DIV_MODE("5"))
//   → clk_pix = 25.2 MHz pixel clock
//
// Reset: hold everything in reset until PLL is locked AND a 4-bit counter
// in the pixel domain reaches bit 3 (8 pixel clocks of stability).
//
// 640×480 timing:
//   H: 640 active + 16 FP + 96 sync + 48 BP = 800 total
//   V: 480 active +  10 FP +  2 sync + 33 BP = 525 total
//   Both syncs negative polarity.
//
// TMDS lane assignment (DVI spec):
//   lane 0 = blue  — carries {vsync, hsync} in blanking periods
//   lane 1 = green — control = 2'b00
//   lane 2 = red   — control = 2'b00
//   lane 3 = clock — constant 10'b0000011111
//
// ELVDS output map:
//   ser[3] → tmds_clk_p/n
//   ser[2] → tmds_d_p[2]/tmds_d_n[2] (red)
//   ser[1] → tmds_d_p[1]/tmds_d_n[1] (green)
//   ser[0] → tmds_d_p[0]/tmds_d_n[0] (blue)

module dvi_tx #(
    parameter PIPE = 1      // pipeline stages in TMDS encoders; 1 = 1 pixel latency
) (
    // Clocks
    input  wire        clk_27,     // 27 MHz board oscillator
    output wire        clk_pix,    // 25.2 MHz pixel clock (driven by PLL chain)
    // Status
    output wire        reset,      // high while PLL settling; use to blank drawing logic
    output wire        frame,      // one clk_pix pulse at start of active frame
    // Pixel coordinates (valid during and outside active region)
    output reg  [9:0]  x,
    output reg  [9:0]  y,
    // Pixel data input (registered on clk_pix; must be stable the cycle before x/y)
    input  wire [23:0] rgb,        // {r[7:0], g[7:0], b[7:0]}
    // HDMI differential pairs
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_d_p,
    output wire [2:0]  tmds_d_n
);

    // ── PLL: 27 MHz → 126 MHz ────────────────────────────────────────────────
    wire clk_x5;
    wire pll_lock;

    rPLL #(
        .FCLKIN         ("27"),
        .DEVICE         ("GW1NR-9C"),
        .IDIV_SEL       (2),           // ÷3 → 9 MHz reference
        .FBDIV_SEL      (13),          // ×14 → 126 MHz output
        .ODIV_SEL       (4),           // VCO = 126 × 4 = 504 MHz
        .DYN_IDIV_SEL   ("false"),
        .DYN_FBDIV_SEL  ("false"),
        .DYN_ODIV_SEL   ("false"),
        .DYN_SDIV_SEL   (2),
        .PSDA_SEL       ("0000"),
        .DYN_DA_EN      ("true"),
        .DUTYDA_SEL     ("1000"),
        .CLKOUT_FT_DIR  (1'b1),
        .CLKOUTP_FT_DIR (1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL      ("internal"),
        .CLKOUT_BYPASS  ("false"),
        .CLKOUTP_BYPASS ("false"),
        .CLKOUTD_BYPASS ("false"),
        .CLKOUTD_SRC    ("CLKOUT"),
        .CLKOUTD3_SRC   ("CLKOUT")
    ) u_pll (
        .CLKIN   (clk_27),
        .CLKOUT  (clk_x5),
        .LOCK    (pll_lock),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKFB   (1'b0),
        .FBDSEL  (6'd0),
        .IDSEL   (6'd0),
        .ODSEL   (6'd0),
        .PSDA    (4'd0),
        .DUTYDA  (4'd0),
        .FDLY    (4'd0)
    );

    // ── CLKDIV: 126 MHz → 25.2 MHz pixel clock ───────────────────────────────
    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) u_clkdiv (
        .HCLKIN(clk_x5),
        .RESETN(pll_lock),
        .CALIB (1'b0),
        .CLKOUT(clk_pix)
    );

    // ── Reset: hold until PLL stable for 8 pixel clocks ──────────────────────
    reg [3:0] rst_cnt = 4'd0;
    assign reset = ~rst_cnt[3];
    always @(posedge clk_pix or negedge pll_lock)
        if (!pll_lock)         rst_cnt <= 4'd0;
        else if (!rst_cnt[3])  rst_cnt <= rst_cnt + 1'b1;

    // ── Pixel counters ────────────────────────────────────────────────────────
    localparam H_ACTIVE = 640, H_FP = 16, H_SYNC = 96, H_TOTAL = 800;
    localparam V_ACTIVE = 480, V_FP = 10, V_SYNC = 2,  V_TOTAL = 525;

    initial x = 10'd0;
    initial y = 10'd0;
    always @(posedge clk_pix) begin
        if (reset) begin
            x <= 10'd0;
            y <= 10'd0;
        end else if (x == H_TOTAL - 1) begin
            x <= 10'd0;
            y <= (y == V_TOTAL - 1) ? 10'd0 : y + 1'b1;
        end else
            x <= x + 1'b1;
    end

    assign frame = (x == 10'd0) && (y == V_ACTIVE);

    // ── Blanking and sync (before pipeline) ──────────────────────────────────
    wire de0 = (x < H_ACTIVE) && (y < V_ACTIVE);
    wire hs0 = ~((x >= H_ACTIVE + H_FP) && (x < H_ACTIVE + H_FP + H_SYNC));
    wire vs0 = ~((y >= V_ACTIVE + V_FP) && (y < V_ACTIVE + V_FP + V_SYNC));

    // Pipeline sync/de to align with the registered rgb input.
    // When PIPE==1 the shift register is a single flip-flop; avoid the
    // PIPE-2 = -1 index issue with Verilog's unsigned parameter arithmetic
    // by using a plain register for that common case.
    reg [PIPE-1:0] de_sr;
    reg [PIPE-1:0] hs_sr;
    reg [PIPE-1:0] vs_sr;
    initial de_sr = {PIPE{1'b0}};
    initial hs_sr = {PIPE{1'b1}};
    initial vs_sr = {PIPE{1'b1}};
    generate
        if (PIPE == 1) begin : pipe1
            always @(posedge clk_pix) begin
                de_sr <= de0;
                hs_sr <= hs0;
                vs_sr <= vs0;
            end
        end else begin : pipn
            always @(posedge clk_pix) begin
                de_sr <= {de_sr[PIPE-2:0], de0};
                hs_sr <= {hs_sr[PIPE-2:0], hs0};
                vs_sr <= {vs_sr[PIPE-2:0], vs0};
            end
        end
    endgenerate
    wire de    = de_sr[PIPE-1];
    wire hsync = hs_sr[PIPE-1];
    wire vsync = vs_sr[PIPE-1];

    // ── TMDS encoders ─────────────────────────────────────────────────────────
    wire [9:0] tmds_b, tmds_g, tmds_r;
    tmds_encoder enc_b (.clk(clk_pix), .reset(reset), .data(rgb[7:0]),   .control({vsync, hsync}), .active(de), .symbol(tmds_b));
    tmds_encoder enc_g (.clk(clk_pix), .reset(reset), .data(rgb[15:8]),  .control(2'b00),          .active(de), .symbol(tmds_g));
    tmds_encoder enc_r (.clk(clk_pix), .reset(reset), .data(rgb[23:16]), .control(2'b00),          .active(de), .symbol(tmds_r));

    // ── Serialization ─────────────────────────────────────────────────────────
    // lane[n][0] is transmitted first (LSB first in OSER10 D0..D9 order).
    wire [9:0] lane [0:3];
    assign lane[0] = tmds_b;
    assign lane[1] = tmds_g;
    assign lane[2] = tmds_r;
    assign lane[3] = 10'b0000011111;   // clock lane: 5 ones then 5 zeros

    wire [3:0] ser;
    genvar n;
    generate
        for (n = 0; n < 4; n = n + 1) begin : serialise
            OSER10 oser (
                .D0(lane[n][0]), .D1(lane[n][1]),
                .D2(lane[n][2]), .D3(lane[n][3]),
                .D4(lane[n][4]), .D5(lane[n][5]),
                .D6(lane[n][6]), .D7(lane[n][7]),
                .D8(lane[n][8]), .D9(lane[n][9]),
                .PCLK (clk_pix),
                .FCLK (clk_x5),
                .RESET(reset),
                .Q    (ser[n])
            );
        end
    endgenerate

    // ── Differential output ───────────────────────────────────────────────────
    // ser[3] → clock, ser[2:0] → data lanes (red/green/blue match index).
    ELVDS_OBUF obuf [3:0] (
        .I ({ser[3],     ser[2],     ser[1],     ser[0]    }),
        .O ({tmds_clk_p, tmds_d_p[2], tmds_d_p[1], tmds_d_p[0]}),
        .OB({tmds_clk_n, tmds_d_n[2], tmds_d_n[1], tmds_d_n[0]})
    );

endmodule
