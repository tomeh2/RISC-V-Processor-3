library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity execution_unit_tb is

end execution_unit_tb;

architecture Behavioral of execution_unit_tb is
    signal clk : std_logic;
    signal rst : std_logic;

    signal uop : T_uop;
    signal cdb : T_uop;

    type T_uop_memory is array (0 to 31) of T_uop;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    rst <= '1', '0' after RST_DURATION;

    process
        variable uop_memory : T_uop_memory;
        variable curr_id : integer := 0;
    begin
        --wait until rst = '0';
        for i in range 0 to 31 loop
            uop <= F_gen_uop_arith(curr_id);
            uop_memory(curr_id) := uop;
            curr_id := curr_id + 1;
        end loop;
    end process;

    uut : entity work.execution_unit
    port map(uop    => uop,
             cdb    => cdb,
             clk    => clk,
             reset  => rst);
end Behavioral;
