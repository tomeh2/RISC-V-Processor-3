library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity back_end_tb is

end back_end_tb;

architecture Behavioral of back_end_tb is
    constant TEST_ID : integer := 2;
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
                if TEST_ID = 0 then
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
                elsif TEST_ID = 1 then
                    uop_after_decode <= F_gen_uop(id,
                                                  X"0000_0000",
                                                  X"0",
                                                  X"10",
                                                  std_logic_vector(to_unsigned(id * 2 ** 8, DATA_WIDTH)),
                                                  id,
                                                  id + 1,
                                                  id + 2,
                                                  id,
                                                  id + 1,
                                                  id + 2,
                                                  '1',
                                                  '1');
                elsif TEST_ID = 2 then
                    uop_after_decode <= F_gen_uop(id,
                                                  X"0000_0000",
                                                  X"0",
                                                  X"10",
                                                  std_logic_vector(to_unsigned(id * 2 ** 8, DATA_WIDTH)),
                                                  id,
                                                  id + 1,
                                                  id + 2,
                                                  id,
                                                  id + 1,
                                                  id + 2,
                                                  '1',
                                                  '1',
                                                  "1000",
                                                  "1111");
                end if;
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