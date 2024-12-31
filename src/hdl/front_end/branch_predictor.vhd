library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity branch_predictor is
    port(
        clk: in std_logic;
        uop_in: in T_uop;
        cdb_in: in T_uop;
        branch_predictor_taken: out std_logic;
        branch_predictor_target_pc: out unsigned(ADDR_WIDTH - 1 downto 0)
    );
end branch_predictor;

architecture rtl of branch_predictor is
    signal btb_executed_branch_update_en: std_logic;
    signal btb_predicted_target: unsigned(ADDR_WIDTH - 1 downto 0);
    signal bp_executed_branch_update_en: std_logic;
    signal bp_pred_taken: std_logic;
begin
    G_bp_type: if BP_TYPE = STATIC generate
        I_static: entity work.branch_predictor_static
        generic map(ADDR_WIDTH => ADDR_WIDTH,
                    PREDICTION => BP_STATIC_PREDICTION)
        port map(clk => clk,
                 branch_pc => uop_in.pc,
                 branch_taken_prediction => bp_pred_taken,
                 executed_branch_pc => (others => '0'),
                 executed_branch_taken => '0',
                 executed_branch_update_en => '0');
        branch_predictor_taken <= bp_pred_taken when uop_in.funct(9 downto 7) = "101" else '1';
    elsif BP_TYPE = SATCNT generate
        I_satcnt: entity work.branch_predictor_satcnt
        generic map(ADDR_WIDTH => ADDR_WIDTH,
                    BITS_PER_COUNTER => BP_SATCNT_N,
                    ENTRIES => BP_SATCNT_ENTRIES)
        port map(clk => clk,
                 branch_pc => uop_in.pc,
                 branch_taken_prediction => bp_pred_taken,
                 executed_branch_pc => cdb_in.pc,
                 executed_branch_taken => cdb_in.branch_taken,
                 executed_branch_update_en => bp_executed_branch_update_en);
        -- We only need to do this prediction for conditional branches since jumps are always taken
        bp_executed_branch_update_en <= '1' when cdb_in.valid = '1' and
                                                 cdb_in.is_speculative_br = '1' and
                                                 cdb_in.funct(9 downto 7) = "101" else '0';
        branch_predictor_taken <= bp_pred_taken when uop_in.funct(9 downto 7) = "101" else '1';
    end generate;

    G_btb: if BTB_ENABLE = true generate
        I_target_predictor: entity work.branch_target_buffer
        generic map(ADDR_WIDTH => ADDR_WIDTH,
                    ENTRIES => BTB_ENTRIES)
        port map(clk => clk,
                 branch_pc => uop_in.pc,
                 branch_target_prediction => btb_predicted_target,
                 executed_branch_pc => cdb_in.pc,
                 executed_branch_target => unsigned(cdb_in.branch_target_addr),
                 executed_branch_update_en => btb_executed_branch_update_en);
        btb_executed_branch_update_en <= '1' when cdb_in.valid = '1' and
                                                  cdb_in.is_speculative_br = '1' and
                                                  cdb_in.branch_taken = '1' and
                                                  cdb_in.funct(9 downto 7) = "010" else '0';

        -- Only use BTB when predicting addresses for JALR instructions, since target PC for others
        -- can be determined immediately by summing the instruction's PC and immediate value
        branch_predictor_target_pc <= btb_predicted_target when uop_in.funct(9 downto 7) = "010" else
          uop_in.pc + unsigned(uop_in.immediate);
    else generate
        branch_predictor_target_pc <= uop_in.pc + unsigned(uop_in.immediate);
    end generate;
end rtl;
