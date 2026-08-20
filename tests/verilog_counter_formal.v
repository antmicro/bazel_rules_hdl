module verilog_counter_formal (
    input wire clk,
    input wire reset,
    output [128:0] out
);
  reg [128:0] counter_tmp;
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      counter_tmp <= 0;
    end else begin
      counter_tmp <= counter_tmp + 1;
    end
  end

  assign out = counter_tmp;

  // Assume that we are coming out of reset before checking anything
  bit f_past_valid;
  initial f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;
  always_comb if (!f_past_valid) assume (reset);

  // The first cycle after reset will be 0
  always @(posedge clk) begin
    if (!reset && !$past(reset) && ($past(counter_tmp) != '1))
      assert (counter_tmp > $past(counter_tmp));
    if (!reset && !$past(reset) && ($past(counter_tmp) == '1)) assert (counter_tmp == '0);
  end
  always @(posedge clk) if (!reset) cover (counter_tmp == 0);
  always @(posedge clk) if (!reset) cover (counter_tmp == 3);
endmodule
