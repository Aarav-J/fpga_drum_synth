`timescale 1ns/1ps
module sequencer_bpm_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg play = 0;
    reg [2:0] bpm_idx;
    reg wr_en = 0;
    reg [3:0] wr_step = 0;
    reg clear = 1;
    wire [3:0] step_out;
    wire kick, snare, hihat, open_hat;
    sequencer dut (
        .clk(clk), .play(play), .bpm_idx(bpm_idx),
        .wr_en(wr_en), .wr_step(wr_step), .wr_mask(4'b0001),
        .clear(clear), .step_out(step_out), .trig_kick(kick),
        .trig_snare(snare), .trig_hihat(hihat), .trig_open(open_hat)
    );
    integer idx, step, cycles, expected, elapsed;
    integer bpm [0:7];

    task check_interval;
        input integer interval;
        begin
            elapsed = 0;
            // Observe registered triggers after each clock edge, not the lookup.
            while (elapsed < interval) begin
                @(negedge clk);
                elapsed = elapsed + 1;
                if (kick !== (elapsed == interval))
                    $fatal(1, "BPM %0d: incorrect trigger at cycle %0d, expected %0d", bpm[bpm_idx], elapsed, interval);
            end
            if (snare !== 0 || hihat !== 0 || open_hat !== 0)
                $fatal(1, "Unexpected voice trigger");
        end
    endtask

    initial begin
        bpm[0]=60; bpm[1]=70; bpm[2]=80; bpm[3]=100;
        bpm[4]=120; bpm[5]=140; bpm[6]=160; bpm[7]=180;
        repeat (3) @(negedge clk);
        clear = 0;
        wr_en = 1;
        for (step=0; step<16; step=step+1) begin
            wr_step = step;
            @(negedge clk);
        end
        wr_en = 0;
        for (idx=0; idx<8; idx=idx+1) begin
            play = 0;
            bpm_idx = idx;
            repeat (2) @(negedge clk);
            expected = (27_000_000 * 60) / (bpm[idx] * 4);
            play = 1;
            check_interval(expected);
            $display("PASS: %0d BPM, %0d clocks per step", bpm[idx], expected);
        end
        play = 0;
        bpm_idx = 4;
        repeat (2) @(negedge clk);
        play = 1;
        cycles = 0;
        for (step=0; step<16; step=step+1) begin
            check_interval((27_000_000 * 60) / (120 * 4));
            cycles = cycles + elapsed;
        end
        if (cycles != 27_000_000 * 2 || dut.step_idx !== 4'd0)
            $fatal(1, "120 BPM bar duration or wrap incorrect");
        play = 0;
        repeat (3) @(negedge clk);
        if (kick !== 0 || step_out !== 0)
            $fatal(1, "Pause did not stop triggers and reset position");
        $display("PASS: 120 BPM bar is 54,000,000 clocks (2 seconds); wrap and pause");
        $finish;
    end
endmodule
