library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity register_file_tb is

end register_file_tb;

architecture Behavioral of register_file_tb is
    constant MAX_CYCLES : integer := 100000;

    signal clk : std_logic;
    signal rst : std_logic;

    signal uop_in : T_uop;
    signal uop_out : T_uop;
    signal cdb : T_uop;

    type T_regfile_sim is array (0 to PHYS_REGFILE_ENTRIES - 1)
      of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal M_regfile_sim : T_regfile_sim := (others => (others => '0'));
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
        variable cycles : integer := 0;
        variable uOPs_gen : integer := 0;
        variable uOPs_pass : integer := 0;
        variable uOPs_fail : integer := 0;
        variable stage : integer := 0;
    begin
        if rising_edge(clk) then
            if rst = '0' then
                cycles := cycles + 1;
                if cycles = MAX_CYCLES then
                    report "MAX_CYCLES reached";
                    report "uOPs Generated = " & integer'image(uOPs_gen);
                    report "uOPs Passed = " & integer'image(uOPs_pass);
                    report "uOPs Failed = " & integer'image(uOPs_fail);
                    assert false severity failure;
                end if;
            
                if stage = 0 then
                    uop_in <= F_gen_uop_arith;
                    cdb <= UOP_ZERO;
                    uOPs_gen := uOPs_gen + 1;
                    stage := 1;
                else
                    cdb <= F_gen_uop_arith;
                    uop_in <= UOP_ZERO;
                    uOPs_gen := uOPs_gen + 1;
                    stage := 0;
                end if;

                if cdb.valid = '1' then
                    M_regfile_sim(to_integer(unsigned(cdb.phys_dst_reg))) <= cdb.reg_write_data;
                end if;

                if uop_out.valid = '1' then
                    if (uop_out.reg_read_1_data = M_regfile_sim(to_integer(unsigned(uop_out.phys_src_reg_1))) and
                       uop_out.reg_read_2_data = M_regfile_sim(to_integer(unsigned(uop_out.phys_src_reg_2)))) then
                        uOPs_pass := uOPs_pass + 1;
                    else
                        uOPs_fail := uOPs_fail + 1;
                    end if;
                end if;
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
