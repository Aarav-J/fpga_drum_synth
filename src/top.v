// Step 2: Button input with debounce
//
// S1 (btn[0], pin 4) — increment counter
// S2 (btn[1], pin 3) — reset counter
// LED[5:0]           — display counter in binary (active-low)
//
// Buttons are active-low (pulled to 3V3; pressed = 0).
// Without debounce, one physical press reads as dozens of edges
// as the contacts bounce for ~1-5 ms.
//
// Debounce strategy: the input must hold its new value for DEBOUNCE
// cycles before we accept it as a clean transition.
// 27_000 cycles @ 27 MHz = 1 ms — enough for any mechanical button.

module top (
    input  wire       clk,
    input  wire [1:0] btn,   // active-low: 0 = pressed, 1 = released
    output wire [5:0] led    // active-low: 0 = lit,     1 = off
);

    // ── Debounce ──────────────────────────────────────────────────────────
    // One debounce block per button.
    // btn_clean tracks the stable (settled) state of the button.
    // btn_prev is btn_clean delayed one cycle — used for edge detection.

    localparam DEBOUNCE = 27_000; // 1 ms at 27 MHz

    // S1 — btn[0]
    reg [14:0] db0;                   // 15 bits holds 0..27_000
    reg        s1_clean = 1'b1;       // initialise to "not pressed"
    reg        s1_prev  = 1'b1;

    always @(posedge clk) begin
        s1_prev <= s1_clean;

        if (btn[0] == s1_clean) begin
            db0 <= 0;                 // input matches current state — stable
        end else if (db0 == DEBOUNCE - 1) begin
            s1_clean <= btn[0];       // held long enough — accept new state
            db0      <= 0;
        end else begin
            db0 <= db0 + 1;           // still counting settle time
        end
    end

    // S2 — btn[1]
    reg [14:0] db1;
    reg        s2_clean = 1'b1;
    reg        s2_prev  = 1'b1;

    always @(posedge clk) begin
        s2_prev <= s2_clean;

        if (btn[1] == s2_clean) begin
            db1 <= 0;
        end else if (db1 == DEBOUNCE - 1) begin
            s2_clean <= btn[1];
            db1      <= 0;
        end else begin
            db1 <= db1 + 1;
        end
    end

    // ── Edge detection ────────────────────────────────────────────────────
    // Falling edge on the clean signal = button pressed.
    // s1_prev=1, s1_clean=0 → the button just settled into "pressed".

    wire s1_press = s1_prev & ~s1_clean;   // S1 fell  (1→0)
    wire s2_press = s2_prev & ~s2_clean;   // S2 fell  (1→0)

    // ── Counter ───────────────────────────────────────────────────────────
    reg [5:0] count;

    always @(posedge clk) begin
        if (s2_press)
            count <= 6'd0;            // S2: reset
        else if (s1_press)
            count <= count + 6'd1;    // S1: increment (wraps 63→0)
    end

    // ── Output ────────────────────────────────────────────────────────────
    // Invert once at the pin boundary.
    // count=0  → led=6'b111111 → all off
    // count=1  → led=6'b111110 → LED0 on
    // count=63 → led=6'b000000 → all on
    assign led = ~count;

endmodule
