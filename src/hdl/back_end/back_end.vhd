library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity back_end is
    port(
        uop_1   : in T_uop;

        clk     : in std_logic;
        reset   : in std_logic
    );
end back_end;

architecture rtl of back_end is
    signal R_pipeline_sched : T_uop;

    signal R_pipeline_regfile : T_uop;
    signal R_cdb_eu0 : T_uop;

    signal eu0_stall_in : std_logic;
    signal eu0_stall_out : std_logic;
    signal rf_stall_in : std_logic;
    signal rf_stall_out : std_logic;

    signal cdb : T_uop;
begin
    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => 8)
    port map(uop_in   => uop_1,
             uop_out  => R_pipeline_sched,
             cdb      => cdb,
             clk      => clk,
             reset    => reset);

    rf_stall_in <= eu0_stall_out;
    regfile_inst : entity work.register_file
    port map(uop_1_in   => R_pipeline_sched,
             uop_1_out  => R_pipeline_regfile,
             cdb   => cdb,
             stall_in   => rf_stall_in,
             stall_out  => rf_stall_out,
             clk        => clk,
             reset      => reset);

    eu0_inst : entity work.execution_unit
    port map(uop        => R_pipeline_regfile,
             cdb        => R_cdb_eu0,
             stall_in   => eu0_stall_in,
             stall_out  => eu0_stall_out,
             clk        => clk,
             reset      => reset);
    cdb <= R_cdb_eu0;
    eu0_stall_in <= '0';
end rtl;
