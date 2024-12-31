library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity branch_predictor_static is
    generic(
        ADDR_WIDTH: natural;
        PREDICTION: boolean
    );
    port(
        clk: in std_logic;
        branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        branch_taken_prediction: out std_logic;
        executed_branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        executed_branch_taken: in std_logic;
        executed_branch_update_en: in std_logic
    );
end branch_predictor_static;

architecture rtl of branch_predictor_static is

begin
    branch_taken_prediction <= '1' when PREDICTION = true else '0';
end rtl;
