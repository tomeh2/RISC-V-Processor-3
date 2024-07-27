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
        uop         : in T_uop;
        cdb         : out T_uop;

        -- ============
        -- FLOW CONTROL
        -- ============
        -- Stall in tells this block that whatever logic is connected to its
        -- output is not yet ready for new data
        -- Stall out tells the blocks preceding this one that this block is not
        -- yet ready to receive new data
        stall_in    : in std_logic;
        stall_out   : out std_logic;

        clk         : in std_logic;
        reset       : in std_logic
    );
end execution_unit;

architecture rtl of execution_unit is
    signal R_pipeline : T_uop;
    signal pipeline_next : T_uop;

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

    process(uop, alu_result)
    begin
        pipeline_next <= uop;
        pipeline_next.reg_write_data <= alu_result;
        pipeline_next.branch_mispredicted <= '0';
    end process;

    P_cdb_reg_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline <= UOP_ZERO;
            else
                R_pipeline <= F_pipeline_reg_logic(pipeline_next, R_pipeline, cdb, stall_in);
            end if;
        end if;
    end process;

    cdb <= R_pipeline;
    stall_out <= R_pipeline.valid and stall_in;
end rtl;
