library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_rename is
    port(
        rr_in_port : in T_rr_in_port;
        rr_out_port : out T_rr_out_port;
        cdb : in T_uop;

        stall_in : in std_logic;
        stall_out : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end register_rename;

architecture rtl of register_rename is
    signal R_pipeline : T_uop;
    signal pipeline_next : T_uop;

    signal raa_get_enable : std_logic;
    signal raa_get_tag : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal raa_empty : std_logic;

    signal rat_write_enable_1 : std_logic;
    signal rat_empty : std_logic;
    signal rat_phys_src_reg_1 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal rat_phys_src_reg_2 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal phys_src_reg_1_valid : std_logic;
    signal phys_src_reg_2_valid : std_logic;

    signal take_snapshot_enable : std_logic;
    signal take_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal recover_snapshot_enable : std_logic;
    signal recover_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;

    signal stall : std_logic;
begin
    take_snapshot_enable <= '1' when rr_in_port.branch_mask /= BR_MASK_ZERO and rr_in_port.valid = '1' and stall_in = '0' else '0';
    F_priority_encoder(rr_in_port.branch_mask, take_snapshot_index);
    recover_snapshot_enable <= cdb.branch_mispredicted and cdb.valid;
    F_priority_encoder(cdb.branch_mask, recover_snapshot_index);

    raa_get_enable <= '1' when rr_in_port.valid = '1' and rr_in_port.arch_dst_reg /= ARCH_REG_ZERO and stall_in = '0' else '0';
    raa_inst : entity work.register_alias_allocator
    generic map(MAX_SNAPSHOTS => MAX_SPEC_BRANCHES,
                MASK_LENGTH => PHYS_REGFILE_ENTRIES)
    port map(get_tag => raa_get_tag,
             get_enable => raa_get_enable,
             put_tag => (others => '0'),
             put_enable => '0',
             take_snapshot_enable => take_snapshot_enable,
             take_snapshot_index => take_snapshot_index,
             recover_snapshot_enable => recover_snapshot_enable,
             recover_snapshot_index => recover_snapshot_index,
             empty => raa_empty,
             clk => clk,
             reset => reset);

    rat_write_enable_1 <= raa_get_enable;
    execution_rat_inst : entity work.register_alias_table
    generic map(ENABLE_MISPREDICT_RECOVERY => true)
    port map(arch_read_tag_1 => rr_in_port.arch_src_reg_1,
             arch_read_tag_2 => rr_in_port.arch_src_reg_2,
             phys_read_tag_1 => rat_phys_src_reg_1,
             phys_read_tag_2 => rat_phys_src_reg_2,
             arch_write_tag_1 => rr_in_port.arch_dst_reg,
             phys_write_tag_1 => raa_get_tag,
             write_enable_1 => rat_write_enable_1,
             take_snapshot_enable => take_snapshot_enable,
             take_snapshot_index => take_snapshot_index,
             recover_snapshot_enable => recover_snapshot_enable,
             recover_snapshot_index => recover_snapshot_index,
             clk => clk,
             reset => reset);

    register_validity_table : entity work.register_validity_table
    port map(clk => clk,
             reset => reset,
             read_addr_1 => rat_phys_src_reg_1,
             read_addr_2 => rat_phys_src_reg_2,
             read_out_1 => phys_src_reg_1_valid,
             read_out_2 => phys_src_reg_2_valid,
             set_addr => cdb.phys_dst_reg,
             set_en => cdb.valid,
             unset_addr => raa_get_tag,
             unset_en => rat_write_enable_1);

    rr_out_port.phys_dst_reg <= raa_get_tag;
    rr_out_port.phys_src_reg_1 <= rat_phys_src_reg_1;
    rr_out_port.phys_src_reg_2 <= rat_phys_src_reg_2;
    rr_out_port.phys_src_reg_1_v <= phys_src_reg_1_valid;
    rr_out_port.phys_src_reg_2_v <= phys_src_reg_2_valid;

    stall_out <= raa_empty;
end rtl;
