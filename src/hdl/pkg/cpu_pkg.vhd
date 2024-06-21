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
    -- Converts an integer to a std_logic_vector of specified length
    function F_int_to_vec (N : integer; len : natural) return std_logic_vector;
    -- Returns 1 if op1 is less then op2 (signed numbers)
    function F_compare_signed (op1 : signed; op2 : signed;  len : natural)
        return std_logic_vector;
    -- Returns 1 if op1 is less then op2 (unsigned numbers)
    function F_compare_unsigned (op1 : unsigned; op2 : unsigned; len : natural)
        return std_logic_vector;

    -- =========
    -- CONSTANTS
    -- =========
    -- User Constants
    constant DATA_WIDTH             : integer := 32;
    constant ARCH_REGFILE_ENTRIES   : integer := 32;
    constant PHYS_REGFILE_ENTRIES   : integer := 64;
    constant REORDER_BUFFER_ENTRIES : integer := 32;

    -- Fixed Constants
    constant UOP_ID_WIDTH         : integer := F_min_bits(REORDER_BUFFER_ENTRIES);
    constant UOP_OP_TYPE_WIDTH    : integer := 4;
    constant UOP_OP_SEL_WIDTH     : integer := 8;
    constant PHYS_REG_ADDR_WIDTH  : integer := F_min_bits(PHYS_REGFILE_ENTRIES);
    constant ARCH_REG_ADDR_WIDTH  : integer := F_min_bits(ARCH_REGFILE_ENTRIES);

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

    -- ====================
    -- ALU OPERATION SELECT
    -- ====================
    constant ALU_OP_ADD     : std_logic_vector(3 downto 0) := "0000";
    constant ALU_OP_SLL     : std_logic_vector(3 downto 0) := "0001";   -- Shift Left Logical
    constant ALU_OP_SLT     : std_logic_vector(3 downto 0) := "0010";   -- Set Less Then
    constant ALU_OP_SLTU    : std_logic_vector(3 downto 0) := "0011";   -- Set Less Then Unsigned
    constant ALU_OP_XOR     : std_logic_vector(3 downto 0) := "0100";
    constant ALU_OP_SRL     : std_logic_vector(3 downto 0) := "0101";   -- Shift Right Logical
    constant ALU_OP_OR      : std_logic_vector(3 downto 0) := "0110";
    constant ALU_OP_AND     : std_logic_vector(3 downto 0) := "0111";
    constant ALU_OP_SUB     : std_logic_vector(3 downto 0) := "1000";
    constant ALU_OP_SRA     : std_logic_vector(3 downto 0) := "1001";   -- Shift Right Arith

    -- ===============
    -- DATA STRUCTURES
    -- ===============
    -- uOP (Micro operation) defines all data & control information used in
    -- execution units. uOPs are first produced after instruction decoding
    -- but certain fields get populated in later stages of execution.
    -- uOP data type contains all fields that EUs can use during execution,
    -- but they don't have to use every available field
    type T_uop is record
        -- uOP ID
        id                  : std_logic_vector(UOP_ID_WIDTH - 1 downto 0);
        -- Program counter of the instruction
        pc                  : std_logic_vector(DATA_WIDTH - 1 downto 0);
        -- Identifies which group of operations this instruction belongs to
        -- Scheduler uses this data to determine where to send the operation
        op_type             : std_logic_vector(UOP_OP_TYPE_WIDTH - 1 downto 0);
        -- These bits are passed to execution units and identify which
        -- operation needs to be performed
        op_sel             : std_logic_vector(UOP_OP_SEL_WIDTH - 1 downto 0);
        -- Architectural registers
        arch_src_reg_1      : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        arch_src_reg_2      : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        arch_dst_reg        : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        -- Physical registers
        phys_src_reg_1      : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        phys_src_reg_2      : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        phys_dst_reg        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        -- Operands
        reg_read_1_data     : std_logic_vector(DATA_WIDTH - 1 downto 0);
        reg_read_2_data     : std_logic_vector(DATA_WIDTH - 1 downto 0);
        reg_write_data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
        -- Indicates whether data in the uOP is valid
        valid               : std_logic;
    end record T_uop;

    -- Common Data Bus (CDB) is used to broadcast the results of instruction
    -- execution to various parts of the CPU core. The concept originates
    -- from Tomasulo's algorithm.
    type T_cdb is record
        -- uOP ID
        id                  : std_logic_vector(UOP_ID_WIDTH - 1 downto 0);
        -- Register write
        reg_write_data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
        -- Indicates whether data on the CDB is valid
        valid               : std_logic;
    end record T_cdb;

    constant T_CDB_ZERO : T_cdb := (
        (others => '0'),
        (others => '0'),
        '0'
    );

    constant T_UOP_ZERO : T_uop := (
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        (others => '0'),
        '0'
    );
end package;

package body cpu_pkg is
    function F_min_bits (N : natural) return natural is
    begin
        return integer(ceil(log2(real(N))));
    end function;

    function F_int_to_vec (N : integer; len : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(N, len));
    end function;

    function F_compare_signed (op1 : signed; op2 : signed; len : natural) return std_logic_vector is
        variable result : std_logic_vector(len - 1 downto 0);
    begin
        result := F_int_to_vec(1, len) when op1 < op2 else F_int_to_vec(0, len);
        return result;
    end function;

    function F_compare_unsigned (op1 : unsigned; op2 : unsigned; len : natural) return std_logic_vector is
        variable result : std_logic_vector(len - 1 downto 0);
    begin
        result := F_int_to_vec(1, len) when op1 < op2 else F_int_to_vec(0, len);
        return result;
    end function;
end package body;