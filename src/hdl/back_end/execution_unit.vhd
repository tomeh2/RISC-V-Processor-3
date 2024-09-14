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
        eu_in_port  : in T_uop;
        eu_out_port : out T_uop;

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
    signal cdb_next : T_uop;

    signal alu_operand_1 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_operand_2 : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal alu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    alu_operand_1 <= eu_in_port.reg_read_1_data;
    alu_operand_2 <= eu_in_port.immediate when eu_in_port.funct(4) = '1' else eu_in_port.reg_read_2_data;
    alu_inst : entity work.arithmetic_logic_unit
    port map(operand_1 => alu_operand_1,
             operand_2 => alu_operand_2,
             result    => alu_result,
             op_sel    => eu_in_port.funct(3 downto 0));

    process(eu_in_port, alu_result)
    begin
        cdb_next <= eu_in_port;
        cdb_next.reg_write_data <= alu_result;
        cdb_next.branch_mispredicted <= '0';
    end process;

    eu_out_port <= cdb_next;
    stall_out <= '0';
end rtl;
