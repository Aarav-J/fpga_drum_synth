`timescale 1ns/1ps
module synth_envelope_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg sample_tick = 0;
    reg gate = 0;
    reg [15:0] sample_in = 16'd32767;
    wire [15:0] sample_out;
    integer i, previous, peak, sustain;
    synth_envelope dut(.clk(clk), .sample_tick(sample_tick), .gate(gate),
                       .sample_in(sample_in), .sample_out(sample_out));

    task tick;
        begin
            @(negedge clk); sample_tick = 1;
            @(negedge clk); sample_tick = 0;
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        if (sample_out !== 16'd0) $fatal(1, "Idle envelope must be silent");
        gate = 1;
        repeat (2) @(negedge clk);
        previous = 0;
        peak = 0;
        for (i = 0; i < 10000; i = i + 1) begin
            tick();
            if (^sample_out === 1'bx || sample_out[15]) $fatal(1, "Invalid positive envelope output");
            if (sample_out > peak) peak = sample_out;
            if (i < 100 && sample_out < previous) $fatal(1, "Attack must rise smoothly");
            previous = sample_out;
        end
        sustain = sample_out;
        if (peak <= sustain || sustain <= 0) $fatal(1, "Attack/decay must settle to nonzero sustain");
        repeat (50) begin
            tick();
            if (sample_out != sustain) $fatal(1, "Held sustain changed");
        end
        // Envelope time advances only with real audio sample ticks.
        repeat (100) @(negedge clk);
        if (sample_out != sustain) $fatal(1, "Envelope advanced without a sample tick");
        sample_in = -16'sd16000;
        #1;
        if (!sample_out[15] || $signed(sample_out) < -16000) $fatal(1, "Negative samples lost signed scaling");
        sample_in = 16'd32767;
        gate = 0;
        repeat (2) @(negedge clk);
        if (sample_out == 0) $fatal(1, "Note off hard-muted instead of releasing");
        previous = sample_out;
        repeat (100) begin
            tick();
            if (sample_out > previous) $fatal(1, "Release must decay");
            previous = sample_out;
        end
        if (previous <= 0 || previous >= sustain) $fatal(1, "Release did not begin smoothly");
        gate = 1;
        repeat (2) @(negedge clk);
        tick();
        if (sample_out < previous) $fatal(1, "Retrigger reset the envelope instead of attacking from current level");
        gate = 0;
        repeat (2) @(negedge clk);
        previous = sample_out;
        for (i = 0; i < 30000; i = i + 1) begin
            tick();
            if (sample_out > previous) $fatal(1, "Release increased output");
            previous = sample_out;
        end
        if (sample_out !== 16'd0) $fatal(1, "Release never reached silence");
        $display("PASS: silence, attack, decay, sustain, sample timing, signed output, release and retrigger");
        $finish;
    end
endmodule
