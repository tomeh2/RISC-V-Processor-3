library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

-- This file defines the logic for a part of the register renaming subsystem
-- called the Register Alias Table (RAT).
-- Note that reding is a combinatorial operaion and not synchronous. That is
-- intentional since the output register is contained in the top file for
-- the register renaming subsystem (register_rename.vhd)
entity register_alias_table is
    generic(
        ENABLE_MISPREDICT_RECOVERY : boolean
    );
    port(
        -- Read ports
        arch_read_tag_1 : in std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        arch_read_tag_2 : in std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        phys_read_tag_1 : out std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        phys_read_tag_2 : out std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);

        -- Write port
        arch_write_tag_1 : in std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        phys_write_tag_1 : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        write_enable_1 : in std_logic;

        take_snapshot_enable : in std_logic;
        take_snapshot_index : in integer;
        recover_snapshot_enable : in std_logic;
        recover_snapshot_index : in integer;

        clk : in std_logic;
        reset : in std_logic
    );
end register_alias_table;

architecture rtl of register_alias_table is
    -- Data type which defines the Register Alias Table (RAT). The RAT is a
    -- table which takes the architectural register number (defined in the
    -- software) and maps in to a corresponding physical register (register
    -- that the CPU will do calculations with)
    type T_rat is array (0 to ARCH_REGFILE_ENTRIES - 1) of std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal M_rat : T_rat;
    type T_rat_mispredict_recovery is array (0 to MAX_SPEC_BRANCHES - 1) of T_rat;
    signal M_rat_mispredict_recovery : T_rat_mispredict_recovery;
begin
    P_rat_write_cntrl : process(clk)
        variable mispredict_recovery_slot_id : integer;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Initialization of the RAT memory like this will prevent
                -- synthesis of BRAM, which might or might not be a problem.
                -- Might get more attention in the future.
                M_rat <= (others => (others => '0'));
            else
                if recover_snapshot_enable = '1' and ENABLE_MISPREDICT_RECOVERY = true then
                    M_rat <= M_rat_mispredict_recovery(mispredict_recovery_slot_id);
                else
                    if take_snapshot_enable = '1' and ENABLE_MISPREDICT_RECOVERY = true then
                        mispredict_recovery_slot_id := take_snapshot_index;
                        M_rat_mispredict_recovery(mispredict_recovery_slot_id) <= M_rat;
                    end if;   

                    -- RAT update logic
                    if write_enable_1 = '1' and arch_write_tag_1 /= ARCH_REG_ZERO then
                        M_rat(F_vec_to_int(arch_write_tag_1)) <= phys_write_tag_1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    P_rat_read_cntrl : process(M_rat, arch_read_tag_1, arch_read_tag_2)
    begin
        phys_read_tag_1 <= M_rat(F_vec_to_int(arch_read_tag_1));
        phys_read_tag_2 <= M_rat(F_vec_to_int(arch_read_tag_2));
    end process;
end rtl;