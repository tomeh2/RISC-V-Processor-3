library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

package cpu_pkg is
    -- =========
    -- FUNCTIONS
    -- =========
    -- Returns the minimum number of bits required to address N unique
    -- locations
    function F_min_bits (N : natural) return natural;

    -- =========
    -- CONSTANTS
    -- =========
    constant PHYS_REGFILE_ENTRIES   : integer := 64;

    -- ==================
    -- OPCODE DEFINITIONS
    -- ==================
    -- RV32I
    constant OPCODE_LUI     :  std_logic_vector(6 downto 0) := "0110111";
    constant OPCODE_AUIPC   :  std_logic_vector(6 downto 0) := "0010111";
    constant OPCODE_JAL     :  std_logic_vector(6 downto 0) := "1101111";
    constant OPCODE_JALR    :  std_logic_vector(6 downto 0) := "1100111";
    constant OPCODE_BRANCH  :  std_logic_vector(6 downto 0) := "1100011";
    constant OPCODE_LOAD    :  std_logic_vector(6 downto 0) := "0000011";
    constant OPCODE_STORE   :  std_logic_vector(6 downto 0) := "0100011";
    constant OPCODE_IMM     :  std_logic_vector(6 downto 0) := "0010011";
    constant OPCODE_ARITH   :  std_logic_vector(6 downto 0) := "0110011";
    constant OPCODE_FENCE   :  std_logic_vector(6 downto 0) := "0001111";
    constant OPCODE_ENV     :  std_logic_vector(6 downto 0) := "1110011";
    -- Zicsr
    constant OPCODE_ZICSR   :  std_logic_vector(6 downto 0) := "1110011";

    -- ===============
    -- DATA STRUCTURES
    -- ===============
    type T_uop is record
        -- Program counter of the instruction
        pc              : std_logic_vector(31 downto 0);
        -- Identifies which group of operations this instruction belongs to
        -- Scheduler uses this data to determine where to send the operation
        op_type         : std_logic_vector(3 downto 0);
        -- These bits are passed to execution units and identify which
        -- operation needs to be performed
        control         : std_logic_vector(7 downto 0);
        -- Architectural registers
        arch_src_reg_1  : std_logic_vector(4 downto 0);
        arch_src_reg_2  : std_logic_vector(4 downto 0);
        arch_dst_reg    : std_logic_vector(4 downto 0);
        -- Physical registers
        phys_src_reg_1  : std_logic_vector(F_min_bits(PHYS_REGFILE_ENTRIES) - 1 downto 0);
        phys_src_reg_2  : std_logic_vector(F_min_bits(PHYS_REGFILE_ENTRIES) - 1 downto 0);
        phys_dst_reg    : std_logic_vector(F_min_bits(PHYS_REGFILE_ENTRIES) - 1 downto 0);
    end record T_uop;
end package;

package body cpu_pkg is
    function F_min_bits (N : natural) return natural is
    begin
        return integer(ceil(log2(real(N))));
    end function;
end package body;