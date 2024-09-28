library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

-- This file contains the implementation of a basic scheduler which picks
-- instructions for dispatchment at random if the conditions are met.
-- Basic scheduler should in theory have the worst performance, but
-- it should have fairly low resource usage on FPGAs

-- NUM_OUTPUT_PORT - How many output ports does this instance of the scheduler
-- have. This number corresponds to the max amount of uOPs that the scheduler
-- can issue per cycle
-- OUTPUT_PORT_EXEC_IDS - An array which is used to determine which ports issue
-- which instruction. Putting a value of 2 into the first element of the array
-- means that all uOPs with exec_unit_id of 2 will be sent to port 0
-- Currently IDs must not repeat
entity scheduler is
    generic(
        NUM_OUTPUT_PORT : T_sched_exec_id;
        OUTPUT_PORT_EXEC_IDS : T_sched_exec_id_array;
        ENTRIES : integer
    );
    port(
        uop_in : in T_uop;
        uop_out : out T_uop_array(0 to NUM_OUTPUT_PORT - 1);
        cdb_in : in T_uop;

        -- ============
        -- FLOW CONTROL
        -- ============
        -- Stall in tells this block that whatever logic is connected to its
        -- output is not yet ready for new data
        -- Stall out tells the blocks preceding this one that this block is not
        -- yet ready to receive new data
        stall_in    : in std_logic_vector(NUM_OUTPUT_PORT - 1 downto 0);
        stall_out   : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end scheduler;

architecture rtl of scheduler is
    signal output_reg_stall_array : std_logic_vector(NUM_OUTPUT_PORT - 1 downto 0);

    type T_sched_array is array (0 to ENTRIES - 1) of T_uop;
    signal M_scheduler : T_sched_array;

    signal uop_dispatch : T_uop_array(0 to NUM_OUTPUT_PORT - 1);

    -- Write priority encoder
    signal sched_write_index : integer range 0 to ENTRIES - 1;
    signal sched_write_enable : std_logic;

    -- Dispatch control
    subtype T_sched_dispatch_index is integer range 0 to ENTRIES - 1;
    type T_sched_dispatch_index_array is array (0 to NUM_OUTPUT_PORT - 1) of T_sched_dispatch_index;
    signal sched_dispatch_index_array : T_sched_dispatch_index_array;
    signal sched_dispatch_enable_array : std_logic_vector(0 to NUM_OUTPUT_PORT - 1);

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
    P_sched_dispatch_prio_enc : process(M_scheduler, output_reg_stall_array)
    begin
        for j in 0 to NUM_OUTPUT_PORT - 1 loop
            sched_dispatch_index_array(j) <= 0;
            sched_dispatch_enable_array(j) <= '0';
            for i in ENTRIES - 1 downto 0 loop
                if M_scheduler(i).valid = '1' and
                    M_scheduler(i).reg_read_1_ready = '1' and
                    M_scheduler(i).reg_read_2_ready = '1' and
                    output_reg_stall_array(j) = '0' and
                    M_scheduler(i).exec_unit_id = OUTPUT_PORT_EXEC_IDS(j) then
                        sched_dispatch_index_array(j) <= i;
                        sched_dispatch_enable_array(j) <= '1';
                end if;
            end loop;
        end loop;
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
                    -- Check whether an executed branch is on the CDB and clear
                    -- make sure that the uOP is put into the scheduler with
                    -- the corresponding branch mask bit cleared
                    if cdb_in.valid = '1' and
                       cdb_in.branch_mask /= BR_MASK_ZERO then
                        M_scheduler(sched_write_index).spec_branch_mask <=
                          uop_in.spec_branch_mask and not cdb_in.branch_mask;
                    end if;

                    -- We need to handle a case where the CDB contains
                    -- the result which the next uOP that will be put
                    -- into the scheduler needs. We need to ensure that
                    -- the corresponding register's valid bit is set to
                    -- 1 so that the instruction doesn't get stuck in
                    -- the scheduler
                    if cdb_in.valid = '1' and
                       uop_in.phys_src_reg_1 = cdb_in.phys_dst_reg then
                       M_scheduler(sched_write_index).reg_read_1_ready <= '1';
                    end if;

                    if cdb_in.valid = '1' and
                       uop_in.phys_src_reg_2 = cdb_in.phys_dst_reg then
                       M_scheduler(sched_write_index).reg_read_2_ready <= '1';
                    end if;
                end if;

                -- Monitor the CDB and set register valid bits when
                -- corresponding register's value is generated
                for i in 0 to ENTRIES - 1 loop
                    if M_scheduler(i).valid = '1' then
                        if cdb_in.valid = '1' and
                           cdb_in.phys_dst_reg = M_scheduler(i).phys_src_reg_1 then
                            M_scheduler(i).reg_read_1_ready <= '1';
                        end if;

                        if cdb_in.valid = '1' and
                           cdb_in.phys_dst_reg = M_scheduler(i).phys_src_reg_2 then
                            M_scheduler(i).reg_read_2_ready <= '1';
                        end if;
                    end if;
                end loop;

                -- Check whether an executed branch is on the CDB and clear
                -- the corresponding speculated branches mask bit in all
                -- entries
                for i in 0 to ENTRIES - 1 loop
                    if (M_scheduler(i).valid = '1' and
                          cdb_in.valid = '1' and
                          cdb_in.branch_mask /= BR_MASK_ZERO) then
                        M_scheduler(i).spec_branch_mask <=
                          M_scheduler(i).spec_branch_mask and not cdb_in.branch_mask;
                    end if;
                end loop;

                -- Scheduler dispatch control
                for i in 0 to NUM_OUTPUT_PORT - 1 loop
                    if sched_dispatch_enable_array(i) = '1' then
                        M_scheduler(sched_dispatch_index_array(i)).valid <= '0';
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Selects the next instruction selected for disptach and puts it into
    -- the uop_dispatch signal
    P_dispatch_reg : process(M_scheduler, sched_dispatch_index_array, sched_dispatch_enable_array)
    begin
        for i in 0 to NUM_OUTPUT_PORT - 1 loop
            uop_dispatch(i) <= M_scheduler(sched_dispatch_index_array(i));
            uop_dispatch(i).valid <= sched_dispatch_enable_array(i);
        end loop;
    end process;

    G_gen_out_port_regs : for i in 0 to NUM_OUTPUT_PORT - 1 generate
        process(clk)
        begin
            F_pipeline_reg(uop_dispatch(i), uop_out(i), cdb_in, clk, reset, stall_in(i));
        end process;
        output_reg_stall_array(i) <= stall_in(0) and uop_out(i).valid;
    end generate;

    stall_out <= sched_full;
end rtl;