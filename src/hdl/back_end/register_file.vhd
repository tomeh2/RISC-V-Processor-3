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
    generic(
        NUM_PORTS : natural range 1 to 8
    );
    port(
        uop_in : in T_uop_array(0 to NUM_PORTS - 1);
        uop_out : out T_uop_array(0 to NUM_PORTS - 1);

        cdb_in : in T_uop;
        -- ============
        -- FLOW CONTROL
        -- ============
        -- Stall in tells this block that whatever logic is connected to its
        -- output is not yet ready for new data
        -- Stall out tells the blocks preceding this one that this block is not
        -- yet ready to receive new data
        stall_in    : in std_logic;
        stall_out   : out std_logic_vector(NUM_PORTS - 1 downto 0);

        debug_rat_in : in T_rr_debug;

        clk : in std_logic;
        reset : in std_logic
    );
end register_file;

architecture rtl of register_file is
    signal pipeline_regs_next : T_uop_array(0 to NUM_PORTS - 1); 

    type T_arch_regfile_debug is array (0 to 31) of std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal arch_regfile_debug : T_arch_regfile_debug;

    type T_regfile_entry is record
        data : std_logic_vector(DATA_WIDTH - 1 downto 0);
    end record;

    type T_regfile is array(0 to PHYS_REGFILE_ENTRIES - 1) of T_regfile_entry;
    signal M_regfile : T_regfile;
begin
    G_gen_out_port_regs : for i in 0 to NUM_PORTS - 1 generate
        pipeline_next_cntrl : process(M_regfile, uop_in(i))
        begin
            pipeline_regs_next(i) <= uop_in(i);
            pipeline_regs_next(i).reg_read_1_data <=
                M_regfile(to_integer(unsigned(uop_in(i).phys_src_reg_1))).data;
            pipeline_regs_next(i).reg_read_2_data <=
                M_regfile(to_integer(unsigned(uop_in(i).phys_src_reg_2))).data;
        end process;

        process(clk)
        begin
            F_pipeline_reg(pipeline_regs_next(i), uop_out(i), cdb_in, clk, reset, stall_in);
        end process;
        stall_out(i) <= uop_out(i).valid and stall_in;
    end generate;

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

    P_debug : process(M_regfile, debug_rat_in)
    begin
        for i in 0 to 31 loop
            arch_regfile_debug(i) <= M_regfile(to_integer(unsigned(debug_rat_in(i)))).data;
        end loop;
    end process;
end rtl;