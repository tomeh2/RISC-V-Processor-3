library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

entity reorder_buffer is
    port(
        uop_in : in T_uop;
        uop_out : out T_uop;
        cdb : in T_uop;

        retired_uop : out T_rob;
        retired_uop_valid : out std_logic;

        stall_in : in std_logic;
        stall_out : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end reorder_buffer;

architecture rtl of reorder_buffer is
    type T_rob_memory is array (0 to REORDER_BUFFER_ENTRIES - 1) of T_rob;
    signal M_rob : T_rob_memory;

    signal R_pipeline : T_uop;
    signal pipeline_next : T_uop;
    signal R_uop_head : T_rob;

    signal R_head_index : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal head_index_next : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal R_tail_index : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal tail_index_next : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    type T_pointer_snapshots is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal M_tail_snapshots : T_pointer_snapshots;

    signal rob_write_entry : T_rob;
    signal uop_in_brmask_index : integer;
    signal cdb_brmask_index : integer;
    signal insert_enable : std_logic;
    signal retire_enable : std_logic;

    signal full : std_logic;
    signal empty : std_logic;
begin
    -- TODO: UTILIZATION SNAPSHOT REGISTERS NEED TO DECREMENT BY ONE ON EVERY
    -- RETIREMENT 

    uop_in_brmask_index <= F_brmask_to_index(uop_in.branch_mask);
    cdb_brmask_index <= F_brmask_to_index(cdb.branch_mask);
    full <= '1' when tail_index_next = R_head_index else '0';
    empty <= '1' when R_head_index = R_tail_index else '0';

    insert_enable <= '1' when 
        (uop_in.valid = '1' and full = '0') and (stall_in = '0' or R_pipeline.valid = '0') and
        (cdb.branch_mispredicted = '0' or cdb.valid = '0') else '0';
    retire_enable <= '1' when empty = '0' and R_uop_head.executed = '1' and
        not (cdb.valid = '1' and cdb.branch_mispredicted = '1') else '0';
    rob_write_entry <= F_uop_to_rob_type(uop_in);

    -- This process generates the next value which pointer registers have to
    -- take when they update
    P_next_index_calc : process(R_head_index,
                                R_tail_index,
                                cdb,
                                cdb_brmask_index,
                                insert_enable,
                                retire_enable,
                                M_tail_snapshots)
    begin
        if R_head_index = REORDER_BUFFER_ENTRIES - 1 then
            head_index_next <= to_unsigned(0, UOP_INDEX_WIDTH);
        else
            head_index_next <= R_head_index + 1;
        end if;

        if cdb.valid = '1' and cdb.branch_mispredicted = '1' then
            tail_index_next <= M_tail_snapshots(cdb_brmask_index);
        elsif R_tail_index = REORDER_BUFFER_ENTRIES - 1 then
            tail_index_next <= to_unsigned(0, UOP_INDEX_WIDTH);
        else
            tail_index_next <= R_tail_index + 1;
        end if;
    end process;

    -- This process controls when ROB pointers update
    P_pointer_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_tail_index <= to_unsigned(0, UOP_INDEX_WIDTH);
                R_head_index <= to_unsigned(0, UOP_INDEX_WIDTH);
            else
                if (cdb.valid = '1' and cdb.branch_mispredicted = '1') or
                    insert_enable = '1' then
                    R_tail_index <= tail_index_next;
                end if;

                if retire_enable = '1' then
                    R_head_index <= head_index_next;
                end if;
            end if;
        end if;
    end process;

    P_rob_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then

            else
                -- ROB write logic
                if cdb.valid = '1' and cdb.branch_mispredicted = '1' then

                else
                    if uop_in.valid = '1' and stall_in = '0' and full = '0' then
                        -- Update ROB memory
                        M_rob(to_integer(R_tail_index)) <= rob_write_entry;

                        if uop_in.branch_mask /= BR_MASK_ZERO then
                            M_tail_snapshots(uop_in_brmask_index) <= tail_index_next;
                        end if;
                    end if;
                end if;

                -- ROB read logic
                if retire_enable = '1' then
                    R_uop_head <= M_rob(to_integer(head_index_next));
                else
                    R_uop_head <= M_rob(to_integer(R_head_index));
                end if;
                -- ROB update & mispredict recovery logic
                if cdb.valid = '1' then
                    M_rob(to_integer(cdb.id)).executed <= '1';
                end if;
            end if;
        end if;
    end process;

    -- This process updates the input uOP with the assigned ID and outputs it
    -- in the next cycle
    P_assign_id : process(uop_in, insert_enable)
    begin
        pipeline_next <= uop_in;
        pipeline_next.id <= R_tail_index;
        pipeline_next.valid <= insert_enable and uop_in.valid;
    end process;

    P_pipeline_reg_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline.valid <= '0';
            else
                R_pipeline <= F_pipeline_reg_logic(pipeline_next, R_pipeline, cdb, stall_in);
            end if;
        end if;
    end process;

    uop_out <= R_pipeline;
    retired_uop <= R_uop_head;
    retired_uop_valid <= retire_enable;
    stall_out <= not insert_enable;
end rtl;
 