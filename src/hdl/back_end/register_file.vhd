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
        uop_in : in T_uop;
        uop_out : out T_uop;

        cdb_in : in T_uop;
        -- ============
        -- FLOW CONTROL
        -- ============
        -- Stall in tells this block that whatever logic is connected to its
        -- output is not yet ready for new data
        -- Stall out tells the blocks preceding this one that this block is not
        -- yet ready to receive new data
        stall_in    : in std_logic;
        stall_out   : out std_logic;

        debug_rat_in : in T_rr_debug;

        clk : in std_logic;
        reset : in std_logic
    );
end register_file;

architecture rtl of register_file is
    type T_arch_regfile_debug is array (0 to 31) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal arch_regfile_debug : T_arch_regfile_debug;

    type T_regfile_entry is record
        data : std_logic_vector(DATA_WIDTH - 1 downto 0);
    end record;

    type T_regfile is array(0 to PHYS_REGFILE_ENTRIES - 1) of T_regfile_entry;
    signal M_regfile : T_regfile;

    signal R_pipeline_0 : T_uop;
    signal pipeline_0_next : T_uop;
    signal pipeline_0_stall : std_logic;
begin
    -- Regfile read logic
    -- Note that the read is done asynchronously with this code, but the idea
    -- is that the synthesis tool will realize that this immediately goes into
    -- a register and synthesize synchronous logic anyway
    pipeline_next_cntrl : process(M_regfile, uop_in)
    begin
        pipeline_0_next <= uop_in;
        pipeline_0_next.reg_read_1_data <=
            M_regfile(to_integer(unsigned(uop_in.phys_src_reg_1))).data;
        pipeline_0_next.reg_read_2_data <=
            M_regfile(to_integer(unsigned(uop_in.phys_src_reg_2))).data;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to PHYS_REGFILE_ENTRIES - 1 loop
                    M_regfile(i).data <= (others => '0');
                end loop;
            else
                -- Register write logic
                -- Physical register 0 always contains the value 0
                if cdb_in.valid = '1' and cdb_in.phys_dst_reg /= std_logic_vector(to_unsigned(0, PHYS_REG_ADDR_WIDTH)) then
                    M_regfile(to_integer(unsigned(cdb_in.phys_dst_reg))).data <= cdb_in.reg_write_data;
                end if;
            end if;
        end if;
    end process;
    
    F_pipeline_reg(pipeline_0_next, R_pipeline_0, cdb_in, clk, reset, stall_in, pipeline_0_stall);

    uop_out <= R_pipeline_0;
    stall_out <= pipeline_0_stall;

    P_debug : process(M_regfile, debug_rat_in)
    begin
        for i in 0 to 31 loop
            arch_regfile_debug(i) <= M_regfile(to_integer(unsigned(debug_rat_in(i)))).data;
        end loop;
    end process;
end rtl;