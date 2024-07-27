library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_rename is
    port(
        uop_in : in T_uop;
        uop_out : out T_uop;
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

    signal take_snapshot_enable : std_logic;
    signal take_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal recover_snapshot_enable : std_logic;
    signal recover_snapshot_index : natural range 0 to MAX_SPEC_BRANCHES - 1;

    signal stall : std_logic;
begin
    take_snapshot_enable <= '1' when uop_in.branch_mask /= BR_MASK_ZERO and uop_in.valid = '1' and stall = '0' else '0';
    F_priority_encoder(uop_in.branch_mask, take_snapshot_index);
    recover_snapshot_enable <= cdb.branch_mispredicted and cdb.valid;
    F_priority_encoder(cdb.branch_mask, recover_snapshot_index);

    raa_get_enable <= '1' when uop_in.valid = '1' and uop_in.arch_dst_reg /= ARCH_REG_ZERO and stall = '0' else '0';
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
             clk => clk,
             reset => reset);

    pipeline_next.id <= uop_in.id;
    pipeline_next.pc <= uop_in.pc;
    pipeline_next.op_type <= uop_in.op_type;
    pipeline_next.op_sel <= uop_in.op_sel;
    pipeline_next.arch_src_reg_1 <= uop_in.arch_src_reg_1;
    pipeline_next.arch_src_reg_2 <= uop_in.arch_src_reg_2;
    pipeline_next.arch_dst_reg <= uop_in.arch_dst_reg;
    pipeline_next.phys_src_reg_1 <= rat_phys_src_reg_1;
    pipeline_next.phys_src_reg_2 <= rat_phys_src_reg_2;
    pipeline_next.phys_dst_reg <= raa_get_tag;
    pipeline_next.immediate <= uop_in.immediate;
    pipeline_next.reg_read_1_data <= uop_in.reg_read_1_data;
    pipeline_next.reg_read_2_data <= uop_in.reg_read_2_data;
    pipeline_next.reg_write_data <= uop_in.reg_write_data;
    pipeline_next.reg_read_1_ready <= uop_in.reg_read_1_ready;
    pipeline_next.reg_read_2_ready <= uop_in.reg_read_2_ready;
    pipeline_next.branch_mispredicted <= uop_in.branch_mispredicted;
    pipeline_next.branch_mask <= uop_in.branch_mask;
    pipeline_next.spec_branch_mask <= uop_in.spec_branch_mask;
    pipeline_next.valid <= uop_in.valid;

    P_pipeline_reg_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline.valid <= '0';
            else
                R_pipeline <= F_pipeline_reg_logic(pipeline_next, R_pipeline, cdb, stall_in);
            end if;
        end if;
    end process;

    uop_out <= R_pipeline;
    stall <= R_pipeline.valid and stall_in;
    stall_out <= stall;
end rtl;
