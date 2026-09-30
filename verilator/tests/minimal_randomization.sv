module minimal_randomization;

  class P;
    rand bit [7:0] data;
  endclass

  initial begin : proc_waveform
    string trace_file;
    if ($value$plusargs("trace=%s", trace_file)) begin
      $dumpfile(trace_file);
      $dumpvars();
    end
  end

  initial begin
    P pkt;
    pkt = new();
    if (!pkt.randomize() with { data > 200; }) begin
      $fatal(1, "Constrained randomization failed");
    end
    if (pkt.data <= 200) begin
      $fatal(1, "Constraint was not satisfied: data=%0d", pkt.data);
    end
    $display("Constrained randomization succeeded: data=%0d", pkt.data);
    $finish;
  end
endmodule
