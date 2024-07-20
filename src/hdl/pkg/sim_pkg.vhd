library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

use WORK.CPU_PKG.ALL;

package sim_pkg is
    constant INT_MAX : integer := 2147483647;
    constant INT_MIN : integer := -2147483648;

    -- =========
    -- FUNCTIONS
    -- =========
    impure function F_gen_rand_uop return T_uop;
    impure function F_gen_uop(
        id : in integer := 0;
        pc : in std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
        op_type : in std_logic_vector(UOP_OP_TYPE_WIDTH - 1 downto 0) := (others => '0');
        op_sel : in std_logic_vector(UOP_OP_SEL_WIDTH - 1 downto 0) := (others => '0');
        immediate : in std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
        arch_src_reg_1 : in integer := 0;
        arch_src_reg_2 : in integer := 0;
        arch_dst_reg : in integer := 0;
        phys_src_reg_1 : in integer := 0;
        phys_src_reg_2 : in integer := 0;
        phys_dst_reg : in integer := 0;
        src_1_rdy : std_logic := '0';
        src_2_rdy : std_logic := '0';
        branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0) := (others => '0');
        spec_branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0) := (others => '0')
    ) return T_uop;
    impure function F_gen_uop_arith(
        id : in integer := -1
    ) return T_uop;
    impure function F_check_uop_arith(
        uop : in T_uop
    ) return boolean;
    impure function F_gen_uop_after_decode(
        id : in integer := -1;
        op_type : in std_logic_vector(UOP_OP_TYPE_WIDTH - 1 downto 0);
        op_sel : in std_logic_vector(UOP_OP_SEL_WIDTH - 1 downto 0)
        ) return T_uop;

    -- =========
    -- CONSTANTS
    -- =========
    constant CLK_PERIOD : time := 10ns;
    constant RST_DURATION : time := CLK_PERIOD * 10;
    constant INIT_SEED : positive := 999;

    shared variable seed : positive := INIT_SEED;

    -- =====
    -- TYPES
    -- =====
    type T_sim_stats is record
        cycles      : integer;
        uOPs_gen    : integer;
        uOPs_pass   : integer;
        uOPs_fail   : integer;
    end record T_sim_stats;
end package;

package body sim_pkg is
    impure function F_rand(len : integer) return std_logic_vector is
        variable rand_num : real;
        variable rand_vec : std_logic_vector(len - 1 downto 0);
    begin
        for i in 0 to len - 1 loop
            uniform(seed, seed, rand_num);
            if rand_num >= 0.5 then
                rand_vec(i) := '1';
            else
                rand_vec(i) := '0';
            end if;
        end loop;
        return rand_vec;
    end function F_rand;

    impure function F_rand_int(magnitude : integer) return integer is
        variable rand_num : real;
    begin
        uniform(seed, seed, rand_num);
        return integer(round(rand_num * real(magnitude)));
    end function F_rand_int;

    impure function F_gen_uop(
        id : in integer := 0;
        pc : in std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
        op_type : in std_logic_vector(UOP_OP_TYPE_WIDTH - 1 downto 0) := (others => '0');
        op_sel : in std_logic_vector(UOP_OP_SEL_WIDTH - 1 downto 0) := (others => '0');
        immediate : in std_logic_vector(DATA_WIDTH - 1 downto 0) := (others => '0');
        arch_src_reg_1 : in integer := 0;
        arch_src_reg_2 : in integer := 0;
        arch_dst_reg : in integer := 0;
        phys_src_reg_1 : in integer := 0;
        phys_src_reg_2 : in integer := 0;
        phys_dst_reg : in integer := 0;
        src_1_rdy : std_logic := '0';
        src_2_rdy : std_logic := '0';
        branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0) := (others => '0');
        spec_branch_mask : in std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0) := (others => '0')
    ) return T_uop is
        variable uop : T_uop;
    begin
        uop.id := std_logic_vector(to_unsigned(id, UOP_ID_WIDTH));
        uop.pc := pc;
        uop.op_type := op_type;
        uop.op_sel := op_sel;
        uop.immediate := immediate;
        uop.arch_src_reg_1 := std_logic_vector(to_unsigned(arch_src_reg_1, ARCH_REG_ADDR_WIDTH));
        uop.arch_src_reg_2 := std_logic_vector(to_unsigned(arch_src_reg_2, ARCH_REG_ADDR_WIDTH));
        uop.arch_dst_reg := std_logic_vector(to_unsigned(arch_dst_reg, ARCH_REG_ADDR_WIDTH));
        uop.phys_src_reg_1 := std_logic_vector(to_unsigned(phys_src_reg_1, PHYS_REG_ADDR_WIDTH));
        uop.phys_src_reg_2 := std_logic_vector(to_unsigned(phys_src_reg_2, PHYS_REG_ADDR_WIDTH));
        uop.phys_dst_reg := std_logic_vector(to_unsigned(phys_dst_reg, PHYS_REG_ADDR_WIDTH));
        uop.reg_read_1_data := std_logic_vector(to_unsigned(0, DATA_WIDTH));
        uop.reg_read_2_data := std_logic_vector(to_unsigned(0, DATA_WIDTH));
        uop.reg_read_1_ready := src_1_rdy;
        uop.reg_read_2_ready := src_2_rdy;
        uop.reg_write_data := std_logic_vector(to_unsigned(0, DATA_WIDTH));
        uop.branch_mask := branch_mask;
        uop.spec_branch_mask := spec_branch_mask;
        uop.valid := '1';
        return uop;
    end function F_gen_uop;

    impure function F_gen_rand_uop return T_uop is
        variable uop : T_uop;
    begin
        uop.id := F_rand(UOP_ID_WIDTH);
        uop.pc := F_rand(DATA_WIDTH - 2) & "00";    -- 4-byte aligned
        uop.op_type := F_rand(UOP_OP_TYPE_WIDTH);
        uop.op_sel := F_rand(UOP_OP_SEL_WIDTH);
        uop.arch_src_reg_1 := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.arch_src_reg_2 := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.arch_dst_reg := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.phys_src_reg_1 := F_rand(PHYS_REG_ADDR_WIDTH);
        uop.phys_src_reg_2 := F_rand(PHYS_REG_ADDR_WIDTH);
        uop.phys_dst_reg := F_rand(PHYS_REG_ADDR_WIDTH);
        uop.reg_read_1_data := F_rand(DATA_WIDTH);
        uop.reg_read_2_data := F_rand(DATA_WIDTH);
        uop.reg_write_data := (others => '0');
        uop.valid := '1';
        return uop;
    end function F_gen_rand_uop;

    impure function F_gen_uop_after_decode(
        id : in integer := -1;
        op_type : in std_logic_vector(UOP_OP_TYPE_WIDTH - 1 downto 0);
        op_sel : in std_logic_vector(UOP_OP_SEL_WIDTH - 1 downto 0)
        ) return T_uop is
        variable uop : T_uop;
    begin
        if id < 0 then
            uop.id := F_rand(UOP_ID_WIDTH);
        else
            uop.id := std_logic_vector(to_unsigned(id, UOP_ID_WIDTH));
        end if;
        uop.pc := F_rand(DATA_WIDTH - 2) & "00";    -- 4-byte aligned
        uop.op_type := op_type;
        uop.op_sel := op_sel;
        uop.arch_src_reg_1 := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.arch_src_reg_2 := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.arch_dst_reg := F_rand(ARCH_REG_ADDR_WIDTH);
        uop.valid := '1';
        return uop;
    end function F_gen_uop_after_decode;

    impure function F_gen_uop_arith(
        id : in integer := -1
    ) return T_uop is
        variable uop : T_uop;
        variable rand_num : real;
        variable rand_num_pos : positive;
    begin
        uniform(seed, seed, rand_num);
        rand_num_pos := positive(round(9 * rand_num));
        if rand_num_pos = 0 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_ADD);
        elsif rand_num_pos = 1 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SLL);
        elsif rand_num_pos = 2 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SLT);
        elsif rand_num_pos = 3 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SLTU);
        elsif rand_num_pos = 4 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_XOR);
        elsif rand_num_pos = 5 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SRL);
        elsif rand_num_pos = 6 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_OR);
        elsif rand_num_pos = 7 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_AND);
        elsif rand_num_pos = 8 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SUB);
        elsif rand_num_pos = 9 then
            return F_gen_uop(id, "0000", "0000" & ALU_OP_SRA);
        else
            return F_gen_uop(id, "1111", "11111111");
        end if;
        return F_gen_uop(id, "1111", "00000000");
    end function F_gen_uop_arith;

    impure function F_check_uop_arith(
        uop : in T_uop
    ) return boolean is
        variable result : std_logic_vector(DATA_WIDTH - 1 downto 0);
    begin
        if uop.op_sel(3 downto 0) = ALU_OP_ADD then
            result := std_logic_vector(signed(uop.reg_read_1_data) + signed(uop.reg_read_2_data));
        elsif uop.op_sel(3 downto 0) = ALU_OP_SLL then
            result := std_logic_vector(
              unsigned(uop.reg_read_1_data) sll to_integer(unsigned(uop.reg_read_2_data(4 downto 0))));
        elsif uop.op_sel(3 downto 0) = ALU_OP_SLT then
            if signed(uop.reg_read_1_data) < signed(uop.reg_read_2_data) then
                result := std_logic_vector(to_unsigned(1, DATA_WIDTH));
            else
                result := std_logic_vector(to_unsigned(0, DATA_WIDTH));
            end if;
        elsif uop.op_sel(3 downto 0) = ALU_OP_SLTU then
            if unsigned(uop.reg_read_1_data) < unsigned(uop.reg_read_2_data) then
                result := std_logic_vector(to_unsigned(1, DATA_WIDTH));
            else
                result := std_logic_vector(to_unsigned(0, DATA_WIDTH));
            end if;
        elsif uop.op_sel(3 downto 0) = ALU_OP_XOR then
            result := uop.reg_read_1_data xor uop.reg_read_2_data;
        elsif uop.op_sel(3 downto 0) = ALU_OP_SRL then
            result := std_logic_vector(
              unsigned(uop.reg_read_1_data) srl to_integer(unsigned(uop.reg_read_2_data(4 downto 0))));
        elsif uop.op_sel(3 downto 0) = ALU_OP_OR then
            result := uop.reg_read_1_data or uop.reg_read_2_data;
        elsif uop.op_sel(3 downto 0) = ALU_OP_AND then
            result := uop.reg_read_1_data and uop.reg_read_2_data;
        elsif uop.op_sel(3 downto 0) = ALU_OP_SUB then
            result := std_logic_vector(signed(uop.reg_read_1_data) - signed(uop.reg_read_2_data));
        elsif uop.op_sel(3 downto 0) = ALU_OP_SRA then
            result := std_logic_vector(
              unsigned(uop.reg_read_1_data) sra to_integer(unsigned(uop.reg_read_2_data(4 downto 0))));
        end if;

        if result = uop.reg_write_data then
            return true;
        else
            return false;
        end if;
    end function F_check_uop_arith;

    function F_print_sim_stats(sim_stats : T_sim_stats) return boolean is
    begin
        report "MAX_CYCLES reached" & LF &
        "uOPs Generated = " & integer'image(sim_stats.uOPs_gen) & LF &
        "uOPs Passed = " & integer'image(sim_stats.uOPs_pass) & LF &
        "uOPs Failed = " & integer'image(sim_stats.uOPs_fail);
        assert false severity failure;
    end function F_print_sim_stats;
end package body;