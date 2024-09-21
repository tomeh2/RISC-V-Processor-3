library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_rename is
    port(
        uop_in : in T_uop;
        uop_out : out T_uop;
        
        cdb_in : in T_uop;

        rob_in : in T_rob;
        rob_in_valid : in std_logic;

        stall_in : in std_logic;
        stall_out : out std_logic;

        debug_out : out T_rr_debug;

        clk : in std_logic;
        reset : in std_logic
    );
end register_rename;

architecture rtl of register_rename is
    signal R_pipeline_0 : T_uop;
    signal pipeline_0_next : T_uop;

    signal raa_get_enable : std_logic;
    signal raa_get_tag : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal raa_empty : std_logic;

    signal rat_write_enable_1 : std_logic;
    signal rat_phys_src_reg_1 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal rat_phys_src_reg_2 : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
    signal phys_src_reg_1_valid : std_logic;
    signal phys_src_reg_2_valid : std_logic;
    signal phys_dst_reg_retire : std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);

    signal take_snapshot_enable : std_logic;
    signal take_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal recover_snapshot_enable : std_logic;
    signal recover_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
begin
    take_snapshot_enable <= '1' when uop_in.branch_mask /= BR_MASK_ZERO and uop_in.valid = '1' and stall_in = '0' else '0';
    F_priority_encoder(uop_in.branch_mask, take_snapshot_index);
    recover_snapshot_enable <= cdb_in.branch_mispredicted and cdb_in.valid;
    F_priority_encoder(cdb_in.branch_mask, recover_snapshot_index);

    raa_get_enable <= '1' when uop_in.valid = '1' and uop_in.arch_dst_reg /= ARCH_REG_ZERO and stall_in = '0' else '0';
    raa_inst : entity work.register_alias_allocator
    generic map(MAX_SNAPSHOTS => MAX_SPEC_BRANCHES,
                MASK_LENGTH => PHYS_REGFILE_ENTRIES)
    port map(get_tag => raa_get_tag,
             get_enable => raa_get_enable,
             put_tag => phys_dst_reg_retire,
             put_enable => rob_in_valid,
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
    port map(arch_read_tag_1 => uop_in.arch_src_reg_1,
             arch_read_tag_2 => uop_in.arch_src_reg_2,
             phys_read_tag_1 => rat_phys_src_reg_1,
             phys_read_tag_2 => rat_phys_src_reg_2,
             arch_write_tag_1 => uop_in.arch_dst_reg,
             phys_write_tag_1 => raa_get_tag,
             write_enable_1 => rat_write_enable_1,
             take_snapshot_enable => take_snapshot_enable,
             take_snapshot_index => take_snapshot_index,
             recover_snapshot_enable => recover_snapshot_enable,
             recover_snapshot_index => recover_snapshot_index,
             debug_out => open,
             clk => clk,
             reset => reset);

    retirement_rat_inst : entity work.register_alias_table
    generic map(ENABLE_MISPREDICT_RECOVERY => false)
    port map(arch_read_tag_1 => rob_in.arch_dst_reg,
             arch_read_tag_2 => (others => '0'),
             phys_read_tag_1 => phys_dst_reg_retire,
             phys_read_tag_2 => open,
             arch_write_tag_1 => rob_in.arch_dst_reg,
             phys_write_tag_1 => rob_in.phys_dst_reg,
             write_enable_1 => rob_in_valid,
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
        pipeline_0_next <= uop_in;
        pipeline_0_next.phys_dst_reg <= raa_get_tag;
        pipeline_0_next.phys_src_reg_1 <= rat_phys_src_reg_1;
        pipeline_0_next.phys_src_reg_2 <= rat_phys_src_reg_2;
        pipeline_0_next.reg_read_1_ready <= phys_src_reg_1_valid;
        pipeline_0_next.reg_read_2_ready <= phys_src_reg_2_valid;
    end process;

    P_pipeline_0 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_0.valid <= '0';
            else
                R_pipeline_0 <= F_pipeline_reg_logic(pipeline_0_next, R_pipeline_0, cdb_in, stall_in);
            end if;
        end if;
    end process;
    
    uop_out <= R_pipeline_0;
    stall_out <= raa_empty or (stall_in and R_pipeline_0.valid);
end rtl;
