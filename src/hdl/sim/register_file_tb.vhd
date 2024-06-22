library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity register_file_tb is

end register_file_tb;

architecture Behavioral of register_file_tb is
    signal clk : std_logic;
    signal rst : std_logic;

    signal uop_in : T_uop;
    signal uop_out : T_uop;
    signal cdb : T_uop;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    rst <= '1', '0' after RST_DURATION;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' then
                uop_in <= F_gen_uop_arith;
            end if;
        end if;
    end process;

    uut : entity work.register_file
    port map(uop_1_in   => uop_in,
             uop_1_out  => uop_out,
             cdb_1_in  => cdb,
             clk        => clk,
             reset      => rst);
end Behavioral;
