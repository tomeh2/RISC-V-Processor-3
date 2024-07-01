library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity back_end_tb is

end back_end_tb;

architecture Behavioral of back_end_tb is
    constant MAX_CYCLES : integer := 100000;

    signal uop_after_decode : T_uop;

    signal clk : std_logic;
    signal rst : std_logic;
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
        variable id : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                uop_after_decode <= UOP_ZERO;
            else
                uop_after_decode <= F_gen_uop(id,
                                              X"0000_0000",
                                              X"0",
                                              X"10",
                                              std_logic_vector(to_unsigned(1, DATA_WIDTH)),
                                              1,
                                              2,
                                              1,
                                              1,
                                              2,
                                              1);
                id := id + 1;
                if id = 32 then
                    id := 0;
                end if;
            end if;
        end if;
    end process;

    uut : entity work.back_end
    port map(uop_1  => uop_after_decode,
             clk    => clk,
             reset  => rst);
end Behavioral;