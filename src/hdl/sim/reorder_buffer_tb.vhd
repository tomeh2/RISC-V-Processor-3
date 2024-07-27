library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity reorder_buffer_tb is
--  Port ( );
end reorder_buffer_tb;

architecture Behavioral of reorder_buffer_tb is
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
        wait until rising_edge(clk);
        cdb <= UOP_ZERO;
        stall_in <= '0';
        rst <= '1';
        wait for CLK_PERIOD * 10;
        rst <= '0';
        wait for CLK_PERIOD * 10;

        uop_in <= UOP_ZERO;
        -- Fill ROB test (empty, full, util registers)
        for i in 0 to REORDER_BUFFER_ENTRIES + 10 loop
            uop_in <= F_gen_uop(id             => 0,
                                arch_src_reg_1 => 1,
                                arch_src_reg_2 => 2,
                                arch_dst_reg   => 3);
            wait until rising_edge(clk);
        end loop;
        uop_in.valid <= '0';
        
        for i in REORDER_BUFFER_ENTRIES - 1 downto 0 loop
            cdb.id <= to_unsigned(i, UOP_INDEX_WIDTH);
            cdb.valid <= '1';
            wait until rising_edge(clk);
        end loop;
        cdb.id <= to_unsigned(0, UOP_INDEX_WIDTH);
        cdb.valid <= '0';
        
        wait for CLK_PERIOD * 10;
        for i in 0 to REORDER_BUFFER_ENTRIES - 15 loop
            uop_in <= F_gen_uop(id             => 0,
                                arch_src_reg_1 => 1,
                                arch_src_reg_2 => 2,
                                arch_dst_reg   => 3);
            wait until rising_edge(clk);
        end loop;
        uop_in <= F_gen_uop(id             => 0,
                            arch_src_reg_1 => 1,
                            arch_src_reg_2 => 2,
                            arch_dst_reg   => 3,
                            branch_mask => "0010");
        wait until rising_edge(clk);
        uop_in <= UOP_ZERO;
            
        for i in 0 to 5 loop
            uop_in <= F_gen_uop(id             => 0,
                                arch_src_reg_1 => 1,
                                arch_src_reg_2 => 2,
                                arch_dst_reg   => 3);
            wait until rising_edge(clk);
        end loop;
        uop_in <= UOP_ZERO;
        wait for CLK_PERIOD * 10;
        wait until rising_edge(clk);
        cdb.branch_mask <= "0010";
        cdb.branch_mispredicted <= '1';
        cdb.valid <= '1';
        wait until rising_edge(clk);
        cdb.branch_mask <= "0000";
        cdb.branch_mispredicted <= '0';
        cdb.valid <= '0';
        wait;
    end process;

    uut : entity work.reorder_buffer
    port map(uop_in     => uop_in,
             uop_out    => uop_out,
             cdb        => cdb,
             stall_in   => stall_in,
             stall_out  => stall_out,
             clk        => clk,
             reset      => rst);

end Behavioral;
