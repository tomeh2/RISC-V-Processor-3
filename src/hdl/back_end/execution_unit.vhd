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

    signal branch_taken : std_logic;
    signal branch_mispredicted : std_logic;

    signal alu_operand_1 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_operand_2 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    P_alu_op_sel : process(uop_in.is_speculative_br, uop_in.pc, uop_in.reg_read_1_data, uop_in.funct,
        uop_in.reg_read_2_data, uop_in.immediate)
    begin
        if uop_in.is_speculative_br = '1' then
            alu_operand_1 <= std_logic_vector(uop_in.pc);
        else
            alu_operand_1 <= uop_in.reg_read_1_data;
        end if;

        if uop_in.funct(9) = '1' then
            alu_operand_2 <= uop_in.immediate;
        else
            alu_operand_2 <= uop_in.reg_read_2_data;
        end if;
    end process;

    P_br_eval : process(uop_in.is_speculative_br, uop_in.funct)
    begin
        if uop_in.is_speculative_br = '1' then
            if uop_in.funct(8) = '1' then   -- JAL and JALR always jump
                branch_taken <= '1';
            else                            -- Conditional branches
                branch_taken <= '0';
            end if;
        else
            branch_taken <= '0';
        end if;
    end process;
    branch_mispredicted <= '1' when uop_in.is_speculative_br = '1' and
                                    uop_in.branch_pred_taken /= branch_taken else '0';

    alu_inst : entity work.arithmetic_logic_unit
    port map(operand_1 => alu_operand_1,
             operand_2 => alu_operand_2,
             result    => alu_result,
             op_sel    => uop_in.funct(3 downto 0));

    process(uop_in, alu_result, branch_taken, branch_mispredicted)
    begin
        pipeline_0_next <= uop_in;
        pipeline_0_next.reg_write_data <= alu_result;
        pipeline_0_next.branch_taken <= branch_taken;
        pipeline_0_next.branch_mispredicted <= branch_mispredicted;
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
