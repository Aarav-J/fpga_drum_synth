module drum_kick ( 
    input wire clk, 
    input wire trigger, 
    output wire [15:0] sample
); 
    reg active; 
    reg [31:0] pitch, phase; 
    reg [15:0] gain;
    reg [15:0] env_cnt;

    localparam PITCH_START = 32'd31_778_572;  // 200 Hz
    localparam PITCH_END   = 32'd4_768_372;   //  30 Hz
    localparam SWEEP_RATE  = 32'd500;

    always @(posedge clk) begin
        if(trigger) begin
            active <= 1; 
            pitch <= PITCH_START;
            phase <= 0; 
            gain <= 16'd32767; 
            env_cnt <= 0; 
        end else if (active) begin
            if (pitch > PITCH_END + SWEEP_RATE)
                pitch <= pitch - SWEEP_RATE; 
            else 
                pitch <= PITCH_END; 

            
            phase <= phase + pitch; 

            if(env_cnt == 16'd499) begin
                env_cnt <= 0;
                gain <= (gain * 32'd32700) >> 15;
                if (gain < 16'd10)
                    active <= 0; 
            end else 
                env_cnt <= env_cnt + 1; 
        end 
    end 
    
    wire [15:0] sine_out; 
    sine_rom u_rom ( 
        .clk (clk), 
        .addr(phase[31:24]), 
        .data(sine_out)
    ); 

    wire [31:0] product = $signed({{1{sine_out[15]}}, sine_out}) * $signed({1'b0, gain}); 
    assign sample = active ? product[30:15] : 16'h0000; 
endmodule
