// DVI TMDS encoder — standard two-stage encoding:
//   1. Transition minimisation (XOR or XNOR based on 1-count)
//   2. DC balance (signed running-disparity tracking)
//
// Registered output: symbol is ready one clk after data/control/active.
// In blanking (active=0): outputs one of four fixed control tokens and
// resets the running disparity to zero.
// On reset: outputs the {vsync=0,hsync=0} control token and zeroes disparity.

module tmds_encoder (
    input  wire       clk,
    input  wire       reset,
    input  wire [7:0] data,
    input  wire [1:0] control,
    input  wire       active,
    output reg  [9:0] symbol
);

    // Count 1s in the 8-bit input word.
    reg [3:0] data_ones;
    integer   k;
    always @(*) begin
        data_ones = 4'd0;
        for (k = 0; k < 8; k = k + 1)
            data_ones = data_ones + {3'b000, data[k]};
    end

    // Transition-minimised 9-bit word [8]=method (1=XOR, 0=XNOR), [7:0]=data.
    reg [8:0] q_m;
    integer   j;
    always @(*) begin
        q_m[0] = data[0];
        if ((data_ones > 4'd4) || ((data_ones == 4'd4) && !data[0])) begin
            // XNOR: fewer transitions for inputs with many 1s
            for (j = 1; j < 8; j = j + 1)
                q_m[j] = ~(q_m[j-1] ^ data[j]);
            q_m[8] = 1'b0;
        end else begin
            // XOR
            for (j = 1; j < 8; j = j + 1)
                q_m[j] = q_m[j-1] ^ data[j];
            q_m[8] = 1'b1;
        end
    end

    // Count 1s in q_m[7:0].
    reg [3:0] q_m_ones;
    always @(*) begin
        q_m_ones = 4'd0;
        for (k = 0; k < 8; k = k + 1)
            q_m_ones = q_m_ones + {3'b000, q_m[k]};
    end

    // Signed balance of q_m[7:0]: (ones - zeros) = 2*ones - 8.
    wire signed [4:0] balance = $signed({1'b0, q_m_ones}) - 5'sd4;

    // Running disparity: signed, wide enough for max accumulation.
    reg signed [5:0] disparity;

    always @(posedge clk) begin
        if (reset) begin
            symbol    <= 10'b1101010100;   // TERC4 control 00
            disparity <= 6'sd0;
        end else if (!active) begin
            // Four defined control tokens (DVI spec Table 3-4)
            case (control)
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
            endcase
            disparity <= 6'sd0;
        end else begin
            // DC balancing (DVI spec Section 3.3.3)
            if ((disparity == 6'sd0) || (balance == 5'sd0)) begin
                symbol[9]   <= ~q_m[8];
                symbol[8]   <=  q_m[8];
                symbol[7:0] <=  q_m[8] ? q_m[7:0] : ~q_m[7:0];
                if (!q_m[8])
                    disparity <= disparity - $signed({1'b0, balance});
                else
                    disparity <= disparity + $signed({1'b0, balance});
            end else if (((disparity > 6'sd0) && (balance > 5'sd0)) ||
                         ((disparity < 6'sd0) && (balance < 5'sd0))) begin
                symbol    <= {1'b1, q_m[8], ~q_m[7:0]};
                disparity <= disparity - $signed({1'b0, balance}) +
                             (q_m[8] ? 6'sd2 : 6'sd0);
            end else begin
                symbol    <= {1'b0, q_m[8], q_m[7:0]};
                disparity <= disparity + $signed({1'b0, balance}) -
                             (q_m[8] ? 6'sd0 : 6'sd2);
            end
        end
    end

endmodule
