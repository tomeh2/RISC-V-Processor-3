library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

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
    signal branch_taken : std_logic;
    signal branch_mispredicted : std_logic;

    signal alu_funct : std_logic_vector(3 downto 0);
    signal alu_operand_1 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_operand_2 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    P_alu_op_sel : process(uop_in.is_speculative_br, uop_in.pc, uop_in.reg_read_1_data, uop_in.funct,
        uop_in.reg_read_2_data, uop_in.immediate)
    begin
        if uop_in.funct(7) = '1' then
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

    P_br_eval : process(uop_in.is_speculative_br, uop_in.funct, uop_in.reg_read_1_data, uop_in.reg_read_2_data)
        variable branch_cond_eval : std_logic;
    begin
        if uop_in.is_speculative_br = '1' then
            if uop_in.funct(8) = '1' then   -- JAL and JALR always jump
                branch_taken <= '1';
            else                            -- Conditional branches
                case uop_in.funct(2 downto 1) is
                when "00" =>    -- EQUALS
                    branch_cond_eval := '1' when 
                        (signed(uop_in.reg_read_1_data) = signed(uop_in.reg_read_2_data)) else '0';
                when "10" =>    -- LESS THEN
                    branch_cond_eval := '1' when 
                        (signed(uop_in.reg_read_1_data) < signed(uop_in.reg_read_2_data)) else '0';
                when "11" =>    -- LESS THEN UNSIGNED
                    branch_cond_eval := '1' when 
                        (unsigned(uop_in.reg_read_1_data) < unsigned(uop_in.reg_read_2_data)) else '0';
                when others =>
                    branch_cond_eval := '0';
                end case;

                if uop_in.funct(0) = '1' then
                    branch_taken <= not branch_cond_eval;
                else
                    branch_taken <= branch_cond_eval;
                end if;
            end if;
        else
            branch_taken <= '0';
        end if;
    end process;
    branch_mispredicted <= '1' when uop_in.is_speculative_br = '1' and
                                    ((uop_in.branch_pred_target /= alu_result and uop_in.branch_pred_taken = '1') or
                                    uop_in.branch_pred_taken /= branch_taken) else '0';

    alu_inst : entity work.arithmetic_logic_unit
    port map(operand_1 => alu_operand_1,
             operand_2 => alu_operand_2,
             result    => alu_result,
             op_sel    => alu_funct);
    alu_funct <= uop_in.funct(3 downto 0) when uop_in.is_speculative_br = '0' else "0000";

    process(uop_in, alu_result, branch_taken, branch_mispredicted)
    begin
        uop_out <= uop_in;
        uop_out.branch_target_addr <= alu_result;
        uop_out.reg_write_data <= std_logic_vector(uop_in.pc + 4) when uop_in.funct(8) = '1' else alu_result;
        uop_out.branch_taken <= branch_taken;
        uop_out.branch_mispredicted <= branch_mispredicted;
    end process;
    stall_out <= stall_in;
end rtl;
