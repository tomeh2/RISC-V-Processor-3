library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

-- ===========
-- DESCRIPTION
-- ===========
-- The register file holds data on which the processor performs operations.
-- All data must be loaded into the register file before operations can be
-- performed on it. Some processors allow operations to be performed directly
-- on data in memory, but RISC-V doesn't.
-- This register file contains more entries then RISC-V's spec describes.
-- That is due to this processor's use of register renaming.
-- The regfile takes in one or more uOP which don't have their operand fields
-- filled and outputs the same uOPs with those fields filled.

entity register_file is
    port(
        uop_1_in : in T_uop;
        uop_1_out : out T_uop;

        cdb_1_in : in T_uop;

        clk : in std_logic;
        reset : in std_logic
    );
end register_file;

architecture rtl of register_file is
    type T_regfile_entry is record
        data : std_logic_vector(DATA_WIDTH - 1 downto 0);
        valid : std_logic;
    end record;

    type T_regfile is array(0 to PHYS_REGFILE_ENTRIES - 1) of T_regfile_entry;
    signal M_regfile : T_regfile;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to PHYS_REGFILE_ENTRIES - 1 loop
                    M_regfile(i).data <= (others => '0');
                    M_regfile(i).valid <= '1';
                end loop;
                uop_1_out <= UOP_ZERO;
            else
                -- Register write logic
                -- Physical register 0 always contains the value 0
                if cdb_1_in.valid = '1' and cdb_1_in.phys_dst_reg /= std_logic_vector(to_unsigned(0, PHYS_REG_ADDR_WIDTH)) then
                    M_regfile(to_integer(unsigned(cdb_1_in.phys_dst_reg))).data <= cdb_1_in.reg_write_data;
                    M_regfile(to_integer(unsigned(cdb_1_in.phys_dst_reg))).valid <= '1';
                end if;

                -- Register read logic
                if uop_1_in.valid = '1' then
                    -- Copy all fields into the output register
                    uop_1_out <= uop_1_in;
                    -- Read operands
                    uop_1_out.reg_read_1_data <=
                      M_regfile(to_integer(unsigned(uop_1_in.phys_src_reg_1))).data;
                    uop_1_out.reg_read_2_data <=
                      M_regfile(to_integer(unsigned(uop_1_in.phys_src_reg_2))).data;
                else
                    uop_1_out <= UOP_ZERO;
                end if;

                if (uop_1_in.spec_branch_mask and cdb_1_in.branch_mask) /= BR_MASK_ZERO and cdb_1_in.branch_mispredicted = '1' then
                    uop_1_out.valid <= '0';
                end if;
            end if;
        end if;
    end process;
end rtl;