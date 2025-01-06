library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_rename is
    port(
        uop_in: in T_uop;
        uop_out: out T_uop;
        
        cdb_in: in T_uop;

        retired_uop: in T_retired_uop;

        stall: in std_logic;
        ready: out std_logic;

        debug_out: out T_rr_debug;

        clk: in std_logic;
        reset: in std_logic
    );
end register_rename;

architecture rtl of register_rename is
    signal raa_get_enable : std_logic;
    signal raa_get_tag : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal raa_empty : std_logic;

    signal rat_write_enable_1 : std_logic;
    signal rat_phys_src_reg_1 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal rat_phys_src_reg_2 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal phys_src_reg_1_valid : std_logic;
    signal phys_src_reg_2_valid : std_logic;
    signal phys_dst_reg_retire : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);

    signal uop_in_is_branch : std_logic;
    signal uop_in_branch_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal cdb_is_branch : std_logic;
    signal cdb_is_branch_mispredicted : std_logic;
    signal cdb_branch_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
begin
    uop_in_is_branch <= '1' when uop_in.branch_mask /= BR_MASK_ZERO and uop_in.valid = '1' and stall = '0' else '0';
    F_priority_encoder(uop_in.branch_mask, uop_in_branch_index);
    cdb_is_branch <= '1' when cdb_in.branch_mask /= BR_MASK_ZERO and cdb_in.valid = '1' else '0';
    cdb_is_branch_mispredicted <= cdb_in.branch_mispredicted and cdb_in.valid;
    F_priority_encoder(cdb_in.branch_mask, cdb_branch_index);

    raa_get_enable <= '1' when uop_in.valid = '1' and uop_in.arch_dst_reg /= ARCH_REG_ZERO and stall = '0' else '0';
    raa_inst : entity work.register_alias_allocator
    generic map(MAX_SNAPSHOTS => MAX_SPEC_BRANCHES,
                MASK_LENGTH => PHYS_REGFILE_ENTRIES)
    port map(get_tag => raa_get_tag,
             get_enable => raa_get_enable,
             put_tag => phys_dst_reg_retire,
             put_enable => retired_uop.valid,
             take_snapshot_enable => uop_in_is_branch,
             take_snapshot_index => uop_in_branch_index,
             recover_snapshot_enable => cdb_is_branch_mispredicted,
             recover_snapshot_index => cdb_branch_index,
             invalidate_snapshot_enable => cdb_is_branch and not cdb_is_branch_mispredicted,
             invalidate_snapshot_index => cdb_branch_index,
             empty => raa_empty,
             clk => clk,
             reset => reset);

    rat_write_enable_1 <= raa_get_enable;
    execution_rat_inst : entity work.register_alias_table
    generic map(ENABLE_MISPREDICT_RECOVERY => true)
    port map(arch_read_tag_1 => uop_in.arch_src_reg_1,
             arch_read_tag_2 => uop_in.arch_src_reg_2,
             phys_read_tag_1 => rat_phys_src_reg_1,
             phys_read_tag_2 => rat_phys_src_reg_2,
             arch_write_tag_1 => uop_in.arch_dst_reg,
             phys_write_tag_1 => raa_get_tag,
             write_enable_1 => rat_write_enable_1,
             take_snapshot_enable => uop_in_is_branch,
             take_snapshot_index => uop_in_branch_index,
             recover_snapshot_enable => cdb_is_branch_mispredicted,
             recover_snapshot_index => cdb_branch_index,
             debug_out => open,
             clk => clk,
             reset => reset);

    retirement_rat_inst : entity work.register_alias_table
    generic map(ENABLE_MISPREDICT_RECOVERY => false)
    port map(arch_read_tag_1 => retired_uop.arch_dst_reg,
             arch_read_tag_2 => (others => '0'),
             phys_read_tag_1 => phys_dst_reg_retire,
             phys_read_tag_2 => open,
             arch_write_tag_1 => retired_uop.arch_dst_reg,
             phys_write_tag_1 => retired_uop.phys_dst_reg,
             write_enable_1 => retired_uop.valid,
             take_snapshot_enable => '0',
             take_snapshot_index => 0,
             recover_snapshot_enable => '0',
             recover_snapshot_index => 0,
             debug_out => debug_out,
             clk => clk,
             reset => reset);

    register_validity_table : entity work.register_validity_table
    port map(clk => clk,
             reset => reset,
             read_addr_1 => rat_phys_src_reg_1,
             read_addr_2 => rat_phys_src_reg_2,
             read_out_1 => phys_src_reg_1_valid,
             read_out_2 => phys_src_reg_2_valid,
             set_addr => cdb_in.phys_dst_reg,
             set_en => cdb_in.valid,
             unset_addr => raa_get_tag,
             unset_en => rat_write_enable_1);

    process(uop_in, raa_get_tag, rat_phys_src_reg_1, rat_phys_src_reg_2, phys_src_reg_1_valid, phys_src_reg_2_valid)
    begin
        uop_out <= uop_in;
        uop_out.phys_dst_reg <= raa_get_tag;
        uop_out.phys_src_reg_1 <= rat_phys_src_reg_1;
        uop_out.phys_src_reg_2 <= rat_phys_src_reg_2;
        uop_out.reg_read_1_ready <= phys_src_reg_1_valid;
        uop_out.reg_read_2_ready <= phys_src_reg_2_valid;
    end process;
    ready <= not raa_empty;
end rtl;
