library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity execution_unit_tb is

end execution_unit_tb;

architecture Behavioral of execution_unit_tb is
    constant MAX_CYCLES : integer := 100000;

    signal clk : std_logic;
    signal rst : std_logic;

    signal uop : T_uop;
    signal cdb : T_uop;

    type T_scoreboard_entry is record
        uop : T_uop;
        done : std_logic;
        time_since_update: unsigned(7 downto 0);
        valid : std_logic;
    end record;
    type T_scoreboard is array (0 to 31) of T_scoreboard_entry;
    signal scoreboard : T_scoreboard;
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
        variable curr_id : integer := 0;
        variable cycles : integer := 0;
        variable uOPs_gen : integer := 0;
        variable uOPs_pass : integer := 0;
        variable uOPs_fail : integer := 0;
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

                for i in 0 to 31 loop
                    if scoreboard(i).valid = '1' and scoreboard(i).done = '0' then
                        scoreboard(i).time_since_update <= scoreboard(i).time_since_update + 1;

                        if scoreboard(i).time_since_update = to_unsigned(255, 8) then
                            assert false report "Timeout in uOP with ID = " & integer'image(to_integer(unsigned(cdb.id))) severity failure;
                        end if;
                    end if;
                end loop;

                if scoreboard(curr_id).done = '1' or scoreboard(curr_id).valid = '0' or scoreboard(curr_id).valid = 'U' then
                    uop <= F_gen_uop_arith(curr_id);
                    scoreboard(curr_id).uop <= uop;
                    scoreboard(curr_id).done <= '0';
                    scoreboard(curr_id).valid <= '1';
                    scoreboard(curr_id).time_since_update <= (others => '0');
                    curr_id := curr_id + 1;
                    uOPs_gen := uOPs_gen + 1;

                    if curr_id = 32 then
                        curr_id := 0;
                    end if;
                else
                    uop <= UOP_ZERO;
                end if;
            end if;
        end if;

        if rising_edge(clk) then
            if cdb.valid = '1' then
                scoreboard(to_integer(unsigned(cdb.id))).done <= '1';
                scoreboard(to_integer(unsigned(cdb.id))).valid <= '0';
                if F_check_uop_arith(cdb) = false then
                    report "Bad Result:";
                    report "ID: " & integer'image(to_integer(unsigned(cdb.id)));
                    report "OP_SEL: " & integer'image(to_integer(unsigned(cdb.op_sel)));
                    report "OP1: " & integer'image(to_integer(unsigned(cdb.reg_read_1_data)));
                    report "OP2: " & integer'image(to_integer(unsigned(cdb.reg_read_2_data)));
                    report "RESULT: " & integer'image(to_integer(unsigned(cdb.reg_write_data)));
                    uOPs_fail := uOPs_fail + 1;
                else
                    uOPs_pass := uOPs_pass + 1;
                    --report "Good result ID = " & integer'image(to_integer(unsigned(cdb.id)));
                end if;
            end if;
        end if;
    end process;

    uut : entity work.execution_unit
    port map(uop    => uop,
             cdb    => cdb,
             clk    => clk,
             reset  => rst);
end Behavioral;
