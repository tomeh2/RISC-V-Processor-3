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
    signal stall_in : std_logic;
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

    process
    begin
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';

        stall_in <= '0';
            -- RAT write & RAA allocate test
        for i in 0 to 31 loop
            uop_in <= F_gen_uop(arch_src_reg_1 => 0,
                                arch_src_reg_2 => 0,
                                arch_dst_reg   => i);
            if i = 15 then
                stall_in <= '1';
                wait for CLK_PERIOD * 10;
                stall_in <= '0';
            end if;
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
        
        wait until rising_edge(clk);
        rst <= '1';
        wait until rising_edge(clk);
        rst <= '0';

        for i in 0 to 15 loop
            uop_in <= F_gen_uop(arch_src_reg_1 => 0,
                                arch_src_reg_2 => 0,
                                arch_dst_reg   => i);
            if i = 15 then
                uop_in.branch_mask <= "0001";
            end if;
            wait until rising_edge(clk);
        end loop;
        for i in 0 to 15 loop
            uop_in <= F_gen_uop(arch_src_reg_1 => 0,
                                arch_src_reg_2 => 0,
                                arch_dst_reg   => i);
            wait until rising_edge(clk);
        end loop;
        uop_in <= UOP_ZERO;
        cdb.branch_mispredicted <= '1';
        cdb.valid <= '1';
        cdb.branch_mask <= "0001";
        wait until rising_edge(clk);
        cdb.branch_mispredicted <= '0';
        cdb.valid <= '0';
        cdb.branch_mask <= "0000";
        wait;
    end process;

    uut : entity work.register_rename
    port map(uop_in     => uop_in,
             uop_out    => uop_out,
             cdb        => cdb,
             stall_in   => stall_in,
             stall_out  => stall_out,
             clk        => clk,
             reset      => rst);
end Behavioral;
