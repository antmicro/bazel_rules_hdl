`timescale 1ns/1ps

module tb_verilog_counter;

  reg clk;
  reg reset;
  wire [128:0] out;
  string trace_path;

  initial begin
    if ($value$plusargs("trace=%s", trace_path)) begin
      $dumpfile(trace_path);
      $dumpvars(0, tb_top);
    end
  end

  // Clock generation: 4 ns period
  always #2 clk = ~clk;

   // Instantiate DUT
  verilog_counter dut (
    .clk(clk),
    .reset(reset),
    .out(out)
  );

  initial begin
    // Initialize signals
    clk = 0;
    reset = 0;

    // Apply reset
    #2 reset = 1;
    #10;

    $display("After reset: out = %h", out);

    // Release reset
    reset = 0;

    // Check counter increments
    repeat (5) begin
      @(posedge clk);
      #1;
      $display("Time = %0t, Counter = %h", $time, out);
    end

    // Finish simulation
    #20;
    $finish;
  end

endmodule
