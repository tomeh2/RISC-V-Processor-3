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
        uop_in  : in T_uop;
        uop_out : out T_uop;

        cdb_in : in T_uop;

        -- ============
        -- FLOW CONTROL
        -- ============
        stall_in : in std_logic;
        stall_out : out std_logic;

        clk         : in std_logic;
        reset       : in std_logic
    );
end execution_unit;

architecture rtl of execution_unit is
    signal R_pipeline_0 : T_uop;
    signal pipeline_0_next : T_uop;

    signal alu_operand_1 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_operand_2 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    alu_operand_1 <= uop_in.reg_read_1_data;
    alu_operand_2 <= uop_in.immediate when uop_in.funct(9) else uop_in.reg_read_2_data;
    alu_inst : entity work.arithmetic_logic_unit
    port map(operand_1 => alu_operand_1,
             operand_2 => alu_operand_2,
             result    => alu_result,
             op_sel    => uop_in.funct(3 downto 0));

    process(uop_in, alu_result)
    begin
        pipeline_0_next <= uop_in;
        pipeline_0_next.reg_write_data <= alu_result;
        pipeline_0_next.branch_mispredicted <= '0';
    end process;

    P_pipeline_4 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_0.valid <= '0';
            else
                R_pipeline_0 <= F_pipeline_reg_logic(pipeline_0_next, R_pipeline_0, cdb_in, '0');
            end if;
        end if;
    end process;

    uop_out <= R_pipeline_0;
    stall_out <= stall_in and R_pipeline_0.valid;
end rtl;
