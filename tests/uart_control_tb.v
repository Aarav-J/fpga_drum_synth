`timescale 1ns/1ps
module uart_control_tb;
reg clk=0;
always #5 clk=~clk;
reg rx=1;
wire [5:0] led;
wire bck,lrck,din;
top dut(.clk(clk),.btn(2'b11),.uart_rx(rx),.led(led),.bck(bck),.lrck(lrck),.din(din));
integer kicks=0,snares=0,hats=0,opens=0;
always @(posedge clk) begin
 if(dut.man_kick) kicks=kicks+1;
 if(dut.man_snare) snares=snares+1;
 if(dut.man_hihat) hats=hats+1;
 if(dut.man_open) opens=opens+1;
end
task send;
 input [7:0] value;
 integer j;
 begin
 @(negedge clk); rx=0; repeat(234) @(negedge clk);
 for(j=0;j<8;j=j+1) begin rx=value[j]; repeat(234) @(negedge clk); end
 rx=1; repeat(234) @(negedge clk);
 end
endtask
initial begin
 repeat(20) @(negedge clk);
 send("k");
 if(kicks!=1 || dut.u_kick.active!==1'b1) $fatal(1,"UART kick did not fire from power-up");
 repeat(1000) @(negedge clk);
 if(^dut.kick_sample===1'bx || dut.kick_sample==0) $fatal(1,"Kick audio missing");
 send("s"); send("h"); send("H");
 if(snares!=1 || hats!=1 || opens!=1) $fatal(1,"Manual voice commands failed");
 send("B"); send(4); send("W"); send(0); send(5);
 if(dut.bpm_idx!==4 || dut.u_seq.pattern[0]!==5) $fatal(1,"Pattern programming failed");
 send("P"); if(dut.play!==1) $fatal(1,"Play failed");
 send("P"); if(dut.play!==0) $fatal(1,"Pause failed");
 send("C"); repeat(5) @(negedge clk);
 if(dut.u_seq.pattern[0]!==0) $fatal(1,"Clear failed");
 $display("PASS: UART startup, manual voices, kick audio, BPM, pattern, play/pause, clear");
 $finish;
end
endmodule
