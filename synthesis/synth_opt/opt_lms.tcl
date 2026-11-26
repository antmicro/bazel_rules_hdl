# Copyright 2026 bazel_rules_hdl Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Adapted from https://github.com/pulp-platform/croc/tree/main/yosys/scripts

# map dont_touch attribute commonly applied to output-nets of async regs to keep
yosys attrmap -rename dont_touch keep
yosys attrmap -tocase keep -imap keep="true" keep=1
# copy the keep attribute to their driving cells (retain on net for debugging)
yosys attrmvcp -copy -attr keep


# -----------------------------------------------------------------------------
# this section heavily borrows from the yosys synth command:
# synth - check
yosys hierarchy -top $top
yosys check
yosys proc

# synth - coarse:
# similar to yosys synth -run coarse -noalumacc
yosys opt_expr
yosys opt -noff
yosys fsm
yosys wreduce 
yosys peepopt
yosys opt_clean
yosys opt -full
yosys booth
yosys share
yosys opt
yosys memory -nomap
yosys memory_map
yosys opt -fast

yosys opt_dff -sat -nodffe -nosdff
yosys share
yosys opt -full
yosys clean -purge

yosys clean -purge

yosys techmap
yosys opt -fast
yosys clean -purge

# flatten all hierarchy except marked modules
yosys flatten

yosys clean -purge


# -----------------------------------------------------------------------------
# Preserve flip-flop names as far as possible
# split internal nets
yosys splitnets -format __v
# rename DFFs from the driven signal
yosys rename -wire -suffix _reg t:*DFF*
# rename all other cells
yosys autoname t:*DFF* %n
yosys clean -purge


# -----------------------------------------------------------------------------
# mapping to technology
yosys dfflibmap -liberty $stdcell_lib

# call ABC
yosys abc -liberty $stdcell_lib -D $period_ps -script $abc_script -constr $abc_constr {*}$dont_use_args

yosys clean -purge


yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge
