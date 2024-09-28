library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

entity reorder_buffer is
    port(
        uop_in : in T_uop;
        uop_allocated_id : out unsigned(UOP_INDEX_WIDTH - 1 downto 0);

        cdb : in T_uop;

        retired_uop : out T_retired_uop;

        stall_in : in std_logic;
        stall_out : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end reorder_buffer;

architecture rtl of reorder_buffer is
    type T_rob is array (0 to REORDER_BUFFER_ENTRIES - 1) of T_rob_entry;
    signal M_rob : T_rob;

    signal R_head_index : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal head_index_next : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal R_tail_index : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal tail_index_next : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    type T_pointer_snapshots is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal M_tail_snapshots : T_pointer_snapshots;

    signal rob_write_entry : T_rob_entry;
    signal uop_in_brmask_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal cdb_brmask_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal insert_enable : std_logic;
    signal retire_enable : std_logic;

    signal full : std_logic;
    signal empty : std_logic;
begin
    uop_in_brmask_index <= F_brmask_to_index(uop_in.branch_mask);
    cdb_brmask_index <= F_brmask_to_index(cdb.branch_mask);
    full <= '1' when tail_index_next = R_head_index else '0';
    empty <= '1' when R_head_index = R_tail_index else '0';

    insert_enable <= '1' when 
        (uop_in.valid = '1' and full = '0') and (stall_in = '0') and
        (cdb.branch_mispredicted = '0' or cdb.valid = '0') else '0';
    retire_enable <= '1' when empty = '0' and M_rob(to_integer(R_head_index)).executed = '1' and
        not (cdb.valid = '1' and cdb.branch_mispredicted = '1') else '0';

    rob_write_entry.arch_dst_reg <= uop_in.arch_dst_reg;
    rob_write_entry.phys_dst_reg <= uop_in.phys_dst_reg;
    -- Immediately enable retirement for STORE instructions
    rob_write_entry.executed <= '1' when uop_in.exec_unit_id = 1 and uop_in.funct(3) = '1' else '0';

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

                -- ROB update logic
                if cdb.valid = '1' then
                    M_rob(to_integer(cdb.id)).executed <= '1';
                end if;
            end if;
        end if;
    end process;

    uop_allocated_id <= R_tail_index;

    retired_uop.id <= R_head_index;
    retired_uop.arch_dst_reg <= M_rob(to_integer(R_head_index)).arch_dst_reg;
    retired_uop.phys_dst_reg <= M_rob(to_integer(R_head_index)).phys_dst_reg;
    retired_uop.valid <= retire_enable;
    stall_out <= full;
end rtl;
 