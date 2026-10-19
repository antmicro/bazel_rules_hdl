// Copyright 2026 bazel_rules_hdl Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

module lfsr (
    input logic clk,
    input logic rst_n,
    input logic freeze,
    input logic start,
    input logic [31:0] seed,
    output logic [31:0] result
);

  logic next_val;

  assign next_val = result[31] ^ result[29] ^ result[28] ^ result[26];

  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) result <= '0;
    else if (start) result <= seed;
    else if (freeze) result <= result;
    else result <= {result[31:1], next_val};
  end

endmodule
