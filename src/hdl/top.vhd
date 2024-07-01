-- RISC-V Processor 3 Planned Features
-- 1) RV32GC instruction set (RV32IA minimum)
-- 2) Speculative branches
-- 3) Speculative LSU
-- 4) Memory virtualization
-- 5) FPU
-- 6) AXI Bus with bulk transfers
-- 7) I-Cache
-- 8) D-Cache
-- 9) Dual-Issue superscalar
-- 10) Register renaming
-- 11) Potentially multi-core

-- TODO:
-- 1) ALU
-- 2) Execution unit for arithmetic instructions

-- This processor relies quite heavily on the synthesis engine's ability to
-- trim unused signals to simplify connections between modules. Modules
-- therefore take as inputs whole data structures and not just parts that
-- they need, but only use parts that are relevant to them.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is

end top;

architecture rtl of top is

begin


end rtl;
