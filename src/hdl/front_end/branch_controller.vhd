-- This module keeps track of allocated branch masks and allocates branch masks
-- to newly arrived branch uOPs.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use WORK.CPU_PKG.ALL;

entity branch_controller is
    generic(
        BRANCHING_DEPTH : natural
    );
    port(
        clk : in std_logic;
        reset : in std_logic;

        cdb_in : in T_uop;
        uop_in : in T_uop;
        stall_in : in std_logic;
        stall_out : out std_logic;
        
        free_branch_mask : out std_logic_vector(BRANCHING_DEPTH - 1 downto 0)
    );
end branch_controller;

architecture rtl of branch_controller is
    type T_bc_mispredict_recovery_memory is array (0 to BRANCHING_DEPTH - 1) of std_logic_vector(BRANCHING_DEPTH - 1 downto 0);
    signal M_mispredict_recovery_memory : T_bc_mispredict_recovery_memory;

    signal cdb_in_branch_mask_index : natural range 0 to BRANCHING_DEPTH - 1;
    signal free_branch_mask_index : natural range 0 to BRANCHING_DEPTH - 1;
    signal R_used_brmasks_bitmap : std_logic_vector(BRANCHING_DEPTH - 1 downto 0);
    signal full : std_logic; 
begin
    process(R_used_brmasks_bitmap, uop_in.is_speculative_br)
        variable v_free_brmask : std_logic_vector(BRANCHING_DEPTH - 1 downto 0);
        variable v_full : std_logic;
    begin
        v_free_brmask := (others => '0');
        v_full := '1';
        for i in BRANCHING_DEPTH - 1 downto 0 loop
            if R_used_brmasks_bitmap(i) = '0' and v_full = '1' then
                v_free_brmask(i) := '1';
                v_full := '0';
            end if;
        end loop;
        free_branch_mask <= v_free_brmask when uop_in.is_speculative_br = '1' else (others => '0');
        full <= v_full;
    end process;
    F_priority_encoder(free_branch_mask, free_branch_mask_index);
    F_priority_encoder(cdb_in.branch_mask, cdb_in_branch_mask_index);

    process(clk)
        
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_used_brmasks_bitmap <= (others => '0');
            else
                if cdb_in.valid = '1' then
                    R_used_brmasks_bitmap <= R_used_brmasks_bitmap and not cdb_in.branch_mask;

                    for i in 0 to BRANCHING_DEPTH - 1 loop
                        M_mispredict_recovery_memory(i) <= M_mispredict_recovery_memory(i) and not cdb_in.branch_mask;
                    end loop;
                end if;

                if cdb_in.valid = '1' and cdb_in.branch_mispredicted = '1' then
                    R_used_brmasks_bitmap <= M_mispredict_recovery_memory(cdb_in_branch_mask_index);
                elsif uop_in.valid = '1' and uop_in.is_speculative_br = '1' and stall_in = '0' then
                    R_used_brmasks_bitmap <= R_used_brmasks_bitmap or free_branch_mask;

                    if cdb_in.valid = '1' then
                        M_mispredict_recovery_memory(free_branch_mask_index) <= R_used_brmasks_bitmap and not cdb_in.branch_mask;
                    else
                        M_mispredict_recovery_memory(free_branch_mask_index) <= R_used_brmasks_bitmap;
                    end if;
                end if;
            end if;
        end if;
    end process;
    stall_out <= not full;
end rtl;
