library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ============
-- UOP ENCODING
-- ============
-- op_type
-- 3 .. 0 - ALU operation select

-- ========
-- CPU LIBS
-- ========
use WORK.CPU_PKG.ALL;

entity execution_unit is
    port(
        uop     : in T_uop;
        cdb     : out T_uop;

        clk     : in std_logic;
        reset   : in std_logic
    );
end execution_unit;

architecture rtl of execution_unit is
    signal R_pipeline_reg : T_uop;

    signal alu_operand_1 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_operand_2 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    alu_operand_1 <= uop.reg_read_1_data;
    alu_operand_2 <= uop.immediate when uop.op_sel(4) = '1' else uop.reg_read_2_data;
    alu_inst : entity work.arithmetic_logic_unit
    port map(operand_1 => alu_operand_1,
             operand_2 => alu_operand_2,
             result    => alu_result,
             op_sel    => uop.op_sel(3 downto 0));

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_reg <= UOP_ZERO;
            else
                R_pipeline_reg <= uop;
                R_pipeline_reg.reg_write_data <= alu_result;
                if (uop.spec_branch_mask and cdb.branch_mask) /= BR_MASK_ZERO and cdb.branch_mispredicted = '1' then
                    R_pipeline_reg.valid <= '0';
                end if;
            end if;
        end if;
    end process;

    cdb <= R_pipeline_reg;
end rtl;
