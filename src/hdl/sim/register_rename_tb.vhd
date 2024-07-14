library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity register_rename_tb is

end register_rename_tb;

architecture Behavioral of register_rename_tb is
    constant MAX_CYCLES : integer := 100000;

    signal uop_in, uop_out, cdb : T_uop;

    signal stall_out : std_logic;
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

    process
    begin
        if rst = '0' then
            -- RAT write & RAA allocate test
            for i in 0 to 31 loop
                uop_in <= F_gen_uop(arch_src_reg_1 => 0,
                                    arch_src_reg_2 => 0,
                                    arch_dst_reg   => i);
                wait until rising_edge(clk);
            end loop;
            uop_in <= UOP_ZERO;
            wait until rising_edge(clk);
            wait for CLK_PERIOD * 10;
            -- RAT read test
            for i in 0 to 30 loop
                uop_in <= F_gen_uop(arch_src_reg_1 => i,
                                    arch_src_reg_2 => i + 1,
                                    arch_dst_reg   => 0);
                wait until rising_edge(clk);
            end loop;
        end if;
        wait until rising_edge(clk);
    end process;

    uut : entity work.register_rename
    port map(uop_in     => uop_in,
             uop_out    => uop_out,
             cdb        => cdb,
             stall_in   => '0',
             stall_out  => stall_out,
             clk        => clk,
             reset      => rst);
end Behavioral;
