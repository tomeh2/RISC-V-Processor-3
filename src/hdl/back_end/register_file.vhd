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
        rf_in_port : in T_rf_in_port;
        rf_out_port : out T_rf_out_port;

        -- ============
        -- FLOW CONTROL
        -- ============
        -- Stall in tells this block that whatever logic is connected to its
        -- output is not yet ready for new data
        -- Stall out tells the blocks preceding this one that this block is not
        -- yet ready to receive new data
        stall_in    : in std_logic;
        stall_out   : out std_logic;

        cdb : in T_uop;

        clk : in std_logic;
        reset : in std_logic
    );
end register_file;

architecture rtl of register_file is
    type T_regfile_entry is record
        data : std_logic_vector(DATA_WIDTH - 1 downto 0);
    end record;

    type T_regfile is array(0 to PHYS_REGFILE_ENTRIES - 1) of T_regfile_entry;
    signal M_regfile : T_regfile;

    signal R_pipeline : T_uop;
    signal pipeline_next : T_uop;
begin
    -- Regfile read logic
    -- Note that the read is done asynchronously with this code, but the idea
    -- is that the synthesis tool will realize that this immediately goes into
    -- a register and synthesize synchronous logic anyway
    pipeline_next_cntrl : process(M_regfile, rf_in_port)
    begin
        rf_out_port.reg_data_1 <=
            M_regfile(to_integer(unsigned(rf_in_port.phys_src_reg_1))).data;
        rf_out_port.reg_data_2 <=
            M_regfile(to_integer(unsigned(rf_in_port.phys_src_reg_2))).data;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to PHYS_REGFILE_ENTRIES - 1 loop
                    M_regfile(i).data <= (others => '0');
                end loop;
                R_pipeline <= UOP_ZERO;
            else
                -- Register write logic
                -- Physical register 0 always contains the value 0
                if cdb.valid = '1' and cdb.phys_dst_reg /= std_logic_vector(to_unsigned(0, PHYS_REG_ADDR_WIDTH)) then
                    M_regfile(to_integer(unsigned(cdb.phys_dst_reg))).data <= cdb.reg_write_data;
                end if;
            end if;
        end if;
    end process;

    stall_out <= '0';
end rtl;