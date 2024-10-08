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
    -- Converts a std_logic_vector input to an integer
    function F_vec_to_int (N : std_logic_vector) return integer;
    -- Converts a onehot encoded std_logic_vector to an integer which
    -- corresponds to the active bit's number counted from the right
    -- and with rightmost bit having value 0
    procedure F_priority_encoder (signal N : in std_logic_vector; signal value : out natural; signal valid : out std_logic; invert_dir : boolean := false);
    procedure F_priority_encoder (signal N : in std_logic_vector; signal value : out natural);
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
    constant ADDR_WIDTH             : integer := 32;
    constant ARCH_REGFILE_ENTRIES   : integer := 32;
    constant PHYS_REGFILE_ENTRIES   : integer := 64;
    constant REORDER_BUFFER_ENTRIES : integer := 32;
    constant MAX_SPEC_BRANCHES      : integer := 4;
    constant SQ_ENTRIES             : integer := 8;
    constant LQ_ENTRIES             : integer := 8;

    -- Fixed Constants
    constant EXEC_UNIT_ID_WIDTH   : integer := 2;
    constant FUNCT3_WIDTH         : integer := 3;
    constant FUNCT7_WIDTH         : integer := 7;
    constant FUNCT_WIDTH         : integer := FUNCT3_WIDTH + FUNCT7_WIDTH;
    constant PHYS_REG_ADDR_WIDTH  : integer := F_min_bits(PHYS_REGFILE_ENTRIES);
    constant ARCH_REG_ADDR_WIDTH  : integer := F_min_bits(ARCH_REGFILE_ENTRIES);
    constant UOP_INDEX_WIDTH      : integer := F_min_bits(REORDER_BUFFER_ENTRIES);
    constant SQ_TAG_WIDTH         : integer := F_min_bits(SQ_ENTRIES);
    constant LQ_TAG_WIDTH         : integer := F_min_bits(LQ_ENTRIES);
    constant BR_MASK_ZERO  : std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0)
      := (others => '0');
    constant PHYS_REG_ZERO        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0)
      := (others => '0');
    constant ARCH_REG_ZERO        : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0)
      := (others => '0');

    -- ==================
    -- OPCODE DEFINITIONS
    -- ==================
    -- RV32I
    constant OPCODE_LOAD    : std_logic_vector(4 downto 0) := "00000";
    constant OPCODE_STORE   : std_logic_vector(4 downto 0) := "01000";
    constant OPCODE_BRANCH  : std_logic_vector(4 downto 0) := "11000";
    constant OPCODE_OP      : std_logic_vector(4 downto 0) := "01100";
    constant OPCODE_OP_IMM  : std_logic_vector(4 downto 0) := "00100";
    constant OPCODE_AUIPC   : std_logic_vector(4 downto 0) := "00101";
    constant OPCODE_LUI     : std_logic_vector(4 downto 0) := "01101";
    constant OPCODE_JAL     : std_logic_vector(4 downto 0) := "11011";
    constant OPCODE_JALR    : std_logic_vector(4 downto 0) := "11001";

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
        id                  : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
        -- Program counter of the instruction
        pc                  : unsigned(DATA_WIDTH - 1 downto 0);
        -- Identifies which group of operations this instruction belongs to
        -- Scheduler uses this data to determine where to send the operation
        exec_unit_id        : unsigned(EXEC_UNIT_ID_WIDTH - 1 downto 0);
        -- Specifies 
        funct               : std_logic_vector(FUNCT_WIDTH - 1 downto 0);
        -- Architectural registers
        arch_src_reg_1      : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        arch_src_reg_2      : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        arch_dst_reg        : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        -- Physical registers
        phys_src_reg_1      : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        phys_src_reg_2      : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        phys_dst_reg        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        -- Operands
        immediate           : std_logic_vector(DATA_WIDTH - 1 downto 0);
        reg_read_1_data     : std_logic_vector(DATA_WIDTH - 1 downto 0);
        reg_read_2_data     : std_logic_vector(DATA_WIDTH - 1 downto 0);
        reg_write_data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
        -- Operand status signals
        reg_read_1_ready    : std_logic;
        reg_read_2_ready    : std_logic;
        -- Load / Store Unit specific data
        sq_index            : unsigned(SQ_TAG_WIDTH - 1 downto 0);
        lq_index            : unsigned(LQ_TAG_WIDTH - 1 downto 0);
        -- Branch speculation masks
        is_speculative_br   : std_logic;
        branch_pred_taken   : std_logic;
        branch_taken        : std_logic;
        branch_mispredicted : std_logic;
        branch_mask         : std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0);
        branch_target_addr  : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        spec_branch_mask    : std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0);
        -- Indicates whether data in the uOP is valid
        valid               : std_logic;
    end record T_uop;

    -- Common Data Bus (CDB) is used to broadcast the results of instruction
    -- execution to various parts of the CPU core. The concept originates
    -- from Tomasulo's algorithm.
    type T_cdb is record
        -- uOP ID
        id                  : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
        -- Register write
        reg_write_data      : std_logic_vector(DATA_WIDTH - 1 downto 0);
        -- Indicates whether data on the CDB is valid
        valid               : std_logic;
    end record T_cdb;

    -- ROB data holds information necessary to record one instruction in ROB.
    type T_rob_entry is record
        -- Destination registers are required to update reitrement RAT and free
        -- the physical register
        arch_dst_reg        : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        phys_dst_reg        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        -- Indicated whether this instruction has finished execution
        executed            : std_logic;
    end record;

    type T_retired_uop is record
        id              : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
        arch_dst_reg        : std_logic_vector(ARCH_REG_ADDR_WIDTH - 1 downto 0);
        phys_dst_reg        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        valid               : std_logic;
    end record;
    
    type T_lsu_store is record
        -- uOP ID
        id                  : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
        -- Store address
        address             : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        address_valid       : std_logic;
        -- Data to be stored
        data                : std_logic_vector(DATA_WIDTH - 1 downto 0);
        data_size           : std_logic_vector(1 downto 0);
        data_valid          : std_logic;
        -- Was the uOP sent to the bus controller / cache
        dispatched          : std_logic;
        -- Did the RW operation in the bus controller finish
        done                : std_logic;
        -- Did the instruction retire
        retired             : std_logic;
    end record;

    type T_lsu_load is record
        -- uOP ID
        id                  : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
        -- Load address
        address             : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        address_valid       : std_logic;
        -- Data properties
        data_size           : std_logic_vector(1 downto 0);
        -- Destination register of the load uOP
        phys_dst_reg        : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        -- Indicates which stores this uOP depends on
        store_mask          : std_logic_vector(SQ_ENTRIES - 1 downto 0);
        -- Was the uOP sent to the bus controller / cache
        dispatched          : std_logic;
        -- Did the RW operation in the bus controller finish
        done                : std_logic;
    end record;

    type T_lsu_agu_port is record
        address         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        address_valid   : std_logic;
        data            : std_logic_vector(DATA_WIDTH - 1 downto 0);
        data_valid      : std_logic;
        rw              : std_logic;
        sq_tag          : unsigned(SQ_TAG_WIDTH - 1 downto 0);
        lq_tag          : unsigned(LQ_TAG_WIDTH - 1 downto 0);
    end record;

    type T_wishbone_req is record
        adr : std_logic_vector(31 downto 0);
        dat : std_logic_vector(31 downto 0);
        we : std_logic;
        sel : std_logic_vector(3 downto 0);
        stb : std_logic;
        cyc : std_logic;
    end record;
    
    type T_wishbone_resp is record
        dat : std_logic_vector(31 downto 0);
        ack : std_logic;
    end record;

    -- This data type contains all data that the LSU gives the bus controller
    -- so that it can perform a R/W operation
    type T_bus_request is record
        address         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        data            : std_logic_vector(DATA_WIDTH - 1 downto 0);
        data_size       : std_logic_vector(1 downto 0);
        rw              : std_logic;
        valid           : std_logic;
    end record;
    type T_bus_request_array is array (natural range<>) of T_bus_request;

    -- This data type contails all data the the bus controller has to send
    -- back to the LSU once the R/W operation has been processed
    type T_bus_response is record
        data            : std_logic_vector(DATA_WIDTH - 1 downto 0);
        address         : std_logic_vector(ADDR_WIDTH - 1 downto 0);
        rw              : std_logic;    -- Load or store
        valid           : std_logic;    -- Memory request executed and data is on resp bus
        ready           : std_logic;    -- Did the bus controller accept the memory request
    end record;
    type T_bus_response_array is array (natural range<>) of T_bus_response;

    type T_rr_debug is array (0 to 31) of std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);

    constant CDB_ZERO : T_cdb := (
        (others => '0'),
        (others => '0'),
        '0'
    );

    constant UOP_ZERO : T_uop := (
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
        (others => '0'),
        '0',
        '0',
        (others => '0'),
        (others => '0'),
        '0',
        '0',
        '0',
        '0',
        (others => '0'),
        (others => '0'),
        (others => '0'),
        '0'
    );

    constant ROB_ZERO : T_rob_entry := (
        (others => '0'),
        (others => '0'),
        '0'
    );
    
    constant BUS_RESP_ZERO : T_bus_response := (
        (others => '0'),
        (others => '0'),
        '0',
        '0',
        '0'
    );

    -- =========
    --   TYPES
    -- =========
    subtype T_sched_exec_id is integer range 0 to 7;
    type T_sched_exec_id_array is array (0 to 7) of T_sched_exec_id;
    type T_uop_array is array (integer range<>) of T_uop;

    -- ===============================
    -- FUNCTIONS POST TYPE DEFINITIONS
    -- ===============================
    -- This code contains definitions for functions which depend on previously
    -- defined data types which are not available at the beginning
    procedure F_pipeline_reg(signal uop_in : in T_uop;
                             signal R_uop_out : inout T_uop;
                             signal cdb : in T_uop;
                             signal clk : in std_logic;
                             signal reset : in std_logic;
                             signal stall_in : in std_logic);
    -- This function takes a uOP as an input and returns a type which can be
    -- put into the ROB
    function F_uop_to_rob_type (uop : T_uop) return T_rob_entry;
    -- Branchmask to index mapping functions
    function F_brmask_to_index (signal branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0))
      return natural;
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

    function F_vec_to_int (N : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(N));
    end function;

    procedure F_priority_encoder (signal N : in std_logic_vector; signal value : out integer; signal valid : out std_logic; invert_dir : boolean := false) is
        variable temp_value : integer := 0;
        variable temp_valid : std_logic := '0';
    begin
        if invert_dir = false then
            for i in 0 to N'length - 1 loop
                if N(i) = '1' then
                    temp_value := i;
                    temp_valid := '1';
                end if;
            end loop;
        else
            for i in N'length - 1 downto 0 loop
                if N(i) = '1' then
                    temp_value := i;
                    temp_valid := '1';
                end if;
            end loop;
        end if;
        valid <= temp_valid;
        value <= temp_value;
    end procedure;

    procedure F_priority_encoder (signal N : in std_logic_vector; signal value : out natural) is
        variable temp_value : natural := 0;
    begin
        for i in 0 to N'length - 1 loop
            if N(i) = '1' then
                temp_value := i;
            end if;
        end loop;
        value <= temp_value;
    end procedure;

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

    procedure F_pipeline_reg(signal uop_in : in T_uop;
                             signal R_uop_out : inout T_uop;
                             signal cdb : in T_uop;
                             signal clk : in std_logic;
                             signal reset : in std_logic;
                             signal stall_in : in std_logic) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_uop_out.valid <= '0';
            else
                if stall_in = '0' or R_uop_out.valid = '0' then     -- Next instruction can pass
                    R_uop_out <= uop_in;
                    if cdb.valid = '1' then
                        -- Handle branch mispredicts
                        if cdb.branch_mispredicted = '1' then
                            if (uop_in.spec_branch_mask and cdb.branch_mask) /= BR_MASK_ZERO then
                                R_uop_out.valid <= '0';
                            end if;
                        end if;
                        -- Clear speculated branches bit when a branch executes
                        R_uop_out.spec_branch_mask <= uop_in.spec_branch_mask and not cdb.branch_mask;

                        -- Handle register value production
                        if uop_in.phys_src_reg_1 = cdb.phys_dst_reg then
                            R_uop_out.reg_read_1_ready <= '1';
                        end if;

                        if uop_in.phys_src_reg_2 = cdb.phys_dst_reg then
                            R_uop_out.reg_read_2_ready <= '1';
                        end if;
                    end if;
                else
                    if cdb.valid = '1' then
                        if cdb.branch_mispredicted = '1' then
                            if (R_uop_out.spec_branch_mask and cdb.branch_mask) /= BR_MASK_ZERO then
                                R_uop_out.valid <= '0';
                            end if;
                        end if;
                        R_uop_out.spec_branch_mask <= R_uop_out.spec_branch_mask and not cdb.branch_mask;

                        -- Handle register value production
                        if R_uop_out.phys_src_reg_1 = cdb.phys_dst_reg then
                            R_uop_out.reg_read_1_ready <= '1';
                        end if;

                        if R_uop_out.phys_src_reg_2 = cdb.phys_dst_reg then
                            R_uop_out.reg_read_2_ready <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end procedure;

    function F_uop_to_rob_type (uop : T_uop) return T_rob_entry is
        variable rob_var : T_rob_entry;
    begin
        rob_var.arch_dst_reg := uop.arch_dst_reg;
        rob_var.phys_dst_reg := uop.phys_dst_reg;
        rob_var.executed := '0';
        return rob_var;
    end function;

    function F_brmask_to_index (signal branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0))
      return natural is
        variable temp_value : natural range 0 to MAX_SPEC_BRANCHES - 1 := 0;
        variable not_one_hot_error : boolean := false;
    begin
        for i in 0 to MAX_SPEC_BRANCHES - 1 loop
            if branch_mask(i) = '1' then
                if not_one_hot_error = true then
                    assert false severity failure;
                end if;
                temp_value := i;
                not_one_hot_error := true;
            end if;
        end loop;
        return temp_value;
    end function;
end package body;