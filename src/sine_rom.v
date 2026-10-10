module sine_rom( 
    input wire clk, 
    input wire [7:0] addr, 
    output reg [15:0] data
); 
reg [15:0] sine_table [0:255]; 
    initial begin
        $readmemh("src/sine_table.hex", sine_table);
    end

    always @(posedge clk)
        data <= sine_table[addr];

endmodule
