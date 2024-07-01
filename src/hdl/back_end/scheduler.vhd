library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

-- This file contains the implementation of a basic scheduler which picks
-- instructions for dispatchment at random if the conditions are met.
-- Basic scheduler should in theory have the worst performance, but
-- it should have fairly low resource usage on FPGAs
entity scheduler is
    generic(
        ENTRIES : integer
    );
    port(
        uop_in : in T_uop;
        uop_out : out T_uop;

        cdb : in T_uop;

        clk : in std_logic;
        reset : in std_logic
    );
end scheduler;

architecture rtl of scheduler is
    type T_sched_array is array (0 to ENTRIES - 1) of T_uop;
    signal M_scheduler : T_sched_array;

    -- Write priority encoder
    signal sched_write_index : integer;
    signal sched_write_enable : std_logic;

    -- Dispatch control
    signal sched_dispatch_index : integer;
    signal sched_dispatch_enable : std_logic;

    -- Scheduler control signals
    signal sched_full : std_logic;
begin
    -- A combinatorial process which selects an empty scheduler entry into
    -- which the next uOP will be put. The selection is done using a
    -- priority encoder on uOP's valid bits. The priority encoder will
    -- select the entry with the lowest index first, which means that
    -- lower index entries effectively have higher priority 
    P_sched_write_prio_enc : process(M_scheduler)
        variable temp_index : integer;
        variable temp_enable : std_logic;
    begin
        temp_index := ENTRIES - 1;
        temp_enable := '0';
        for i in ENTRIES - 1 downto 0 loop
            if M_scheduler(i).valid = '0' then
                temp_index := i;
                temp_enable := '1';
            end if;
        end loop;
        sched_write_index <= temp_index;
        sched_write_enable <= temp_enable;
    end process;
    sched_full <= not sched_write_enable;

    -- A combinatorial process which selects the next uOP to be dispatched.
    -- The instruction is picked randomly within the subset of valid
    -- instructions. Valid instructions are ones where all operands are
    -- ready and the uOP itself is valid
    P_sched_dispatch_prio_enc : process(M_scheduler)
        variable temp_index : integer;
        variable temp_enable : std_logic;
    begin
        temp_index := ENTRIES - 1;
        temp_enable := '0';
        for i in ENTRIES - 1 downto 0 loop
            if M_scheduler(i).valid = '1' and
               M_scheduler(i).reg_read_1_ready = '1' and
               M_scheduler(i).reg_read_2_ready = '1' then
                temp_index := i;
                temp_enable := '1';
            end if;
        end loop;
        sched_dispatch_index <= temp_index;
        sched_dispatch_enable <= temp_enable;
    end process;

    -- Scheduler entry controller
    -- Controls writing into the scheduler, instruction dispatch and CDB
    -- monitoring for produced data
    P_sched_control : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to ENTRIES - 1 loop
                    M_scheduler(i).valid <= '0';
                end loop;
            else
                -- Scheduler write control
                if uop_in.valid = '1' and sched_full = '0' then
                    M_scheduler(sched_write_index) <= uop_in;

                    -- We need to handle a case where the CDB contains
                    -- the result which the current uop_in requires.
                    -- If we don't include this then we could stumble on a case
                    -- where the operand's valid bit doesn't get set to 1
                    -- and the instruction gets stuck in the scheduler
                    if cdb.valid = '1' and
                       uop_in.valid = '1' and
                       uop_in.phys_src_reg_1 = cdb.phys_dst_reg then
                       M_scheduler(sched_write_index).reg_read_1_ready <= '1';
                    end if;

                    if cdb.valid = '1' and
                       uop_in.valid = '1' and
                       uop_in.phys_src_reg_2 = cdb.phys_dst_reg then
                       M_scheduler(sched_write_index).reg_read_2_ready <= '1';
                    end if;
                end if;

                -- Scheduler dispatch control
                if sched_dispatch_enable = '1' then
                    M_scheduler(sched_dispatch_index).valid <= '0';
                end if;
            end if;
        end if;
    end process;

    P_dispatch_reg : process(clk)
    begin
        if rising_edge(clk) then
            uop_out <= M_scheduler(sched_dispatch_index);
            uop_out.valid <= sched_dispatch_enable;
        end if;
    end process;
end rtl;