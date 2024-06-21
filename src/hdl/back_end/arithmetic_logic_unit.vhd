library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity arithmetic_logic_unit is
    port(
        -- DATA
        operand_1   : in std_logic_vector(DATA_WIDTH - 1 downto 0);
        operand_2   : in std_logic_vector(DATA_WIDTH - 1 downto 0);
        result      : out std_logic_vector(DATA_WIDTH - 1 downto 0);

        -- CONTROL
        op_sel      : in std_logic_vector(3 downto 0)
    );
end arithmetic_logic_unit;

architecture rtl of arithmetic_logic_unit is
    -- Is shift arithmetic
    signal is_arith     : std_logic;
    signal shift_dir    : std_logic;    -- 0 = RIGHT | 1 = LEFT
    -- Barrel shifter result
    signal bs_result    : std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Result of signed comparison
    signal comp_result  : std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- Result of unsigned comparison
    signal compu_result : std_logic_vector(DATA_WIDTH - 1 downto 0);
begin
    is_arith <= '1' when op_sel = ALU_OP_SRA else '0';
    shift_dir <= '1' when op_sel = ALU_OP_SLL else '0';
    barrel_shifter_inst : entity work.barrel_shifter
    port map(operand            => operand_1,
             result             => bs_result,
             shift_amount       => operand_2(4 downto 0),
             shift_arith        => is_arith,
             shift_direction    => shift_dir);

    comp_result <=
      F_compare_signed(signed(operand_1), signed(operand_2), DATA_WIDTH);
    compu_result <=
      F_compare_unsigned(unsigned(operand_1), unsigned(operand_2), DATA_WIDTH);

    with op_sel select result <=
        std_logic_vector(signed(operand_1) + signed(operand_2)) when ALU_OP_ADD,
        bs_result                                               when ALU_OP_SLL,
        comp_result                                             when ALU_OP_SLT,
        compu_result                                            when ALU_OP_SLTU,
        operand_1 xor operand_2                                 when ALU_OP_XOR,
        bs_result                                               when ALU_OP_SRL,
        operand_1 or operand_2                                  when ALU_OP_OR,
        operand_1 and operand_2                                 when ALU_OP_AND,
        std_logic_vector(signed(operand_1) - signed(operand_2)) when ALU_OP_SUB,
        bs_result                                               when ALU_OP_SRA,
        F_int_to_vec(0, DATA_WIDTH)                             when others;
end rtl;
