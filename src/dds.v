module dds (
    input wire clk, 
    input wire [31:0] tuning_word, 
    output wire [15:0] sample
); 
    reg [31:0] phase_accumulator = 32'd0; 

    always @(posedge clk) begin 
        phase_accumulator <= phase_accumulator + tuning_word;
    end
    
    sine_rom u_rom (
        .clk (clk),
        .addr(phase_accumulator[31:24]),
        .data(sample)
    );

endmodule
