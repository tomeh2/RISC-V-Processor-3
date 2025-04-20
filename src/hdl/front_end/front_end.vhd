library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity front_end is
    port(
        clk: in std_logic;
        reset: in std_logic;

        uop_out: out T_uop;
        cdb_in: in T_uop;
        stall_be: in std_logic;
        --icache_ready: in std_logic;

        bus_req: out T_bus_request;
        bus_resp: in T_bus_response
    );
end front_end;

architecture rtl of front_end is
    signal fetch_fifo_instruction_write : std_logic_vector(63 downto 0);
    signal fetch_fifo_instruction_read : std_logic_vector(63 downto 0);
    signal fetch_fifo_put_en : std_logic;
    signal fetch_fifo_get_en : std_logic;
    signal fetch_fifo_almost_full : std_logic;
    signal fetch_fifo_full : std_logic;
    signal fetch_fifo_almost_empty : std_logic;
    signal fetch_fifo_empty : std_logic;

    signal R_pipeline_0_instr : std_logic_vector(31 downto 0);
    signal R_pipeline_0_pc : unsigned(31 downto 0);
    signal R_pipeline_0_valid : std_logic;

    signal icache_cancel_all: std_logic;

    signal stall_fetch : std_logic;
    signal cdb_branch_mispredicted : std_logic;

    signal R_program_counter : unsigned(ADDR_WIDTH - 1 downto 0);

    signal instdec_uop : T_uop;

    signal bc_stall : std_logic;
    signal bc_free_branch_mask : std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0);
    signal bc_spec_branches_mask : std_logic_vector(MAX_SPEC_BRANCHES - 1 downto 0);

    signal bp_pred_target_pc: unsigned(ADDR_WIDTH - 1 downto 0);
    signal bp_pred_taken: std_logic;
    signal bp_pred_valid: std_logic;

    type T_pipeline_reg_test is record
        data: std_logic_vector(63 downto 0);
        valid: std_logic;
    end record;
    signal R_fifo_pipeline: T_pipeline_reg_test;
begin
    cdb_branch_mispredicted <= cdb_in.valid and cdb_in.branch_mispredicted;
    bp_pred_valid <= bp_pred_taken and instdec_uop.valid and instdec_uop.is_speculative_br;
    icache_cancel_all <= cdb_branch_mispredicted or (bp_pred_taken and instdec_uop.valid and instdec_uop.is_speculative_br);
    -- ===================================
    --      INSTRUCTION FETCH LOGIC
    -- ===================================
    I_fetch_fifo : entity work.fifo
    generic map(BITS_PER_ENTRY => 64,
                OUTPUT_REG_ENABLE => false,
                ENTRIES => FETCH_FIFO_ENTRIES)
    port map(clk                => clk,
             reset              => reset or cdb_branch_mispredicted or bp_pred_valid,
             data_in            => fetch_fifo_instruction_write,
             data_out           => fetch_fifo_instruction_read,
             get_en             => fetch_fifo_get_en,
             put_en             => fetch_fifo_put_en,
             almost_full        => fetch_fifo_almost_full,
             full               => fetch_fifo_full,
             almost_empty       => fetch_fifo_almost_empty,
             empty              => fetch_fifo_empty);
    fetch_fifo_instruction_write(63 downto 32) <= std_logic_vector(bus_resp.address);
    fetch_fifo_instruction_write(31 downto 0) <= bus_resp.data;

    fetch_fifo_put_en <= '1' when bus_resp.valid = '1' and cdb_branch_mispredicted /= '1' else '0';
    fetch_fifo_get_en <= not (R_fifo_pipeline.valid and (stall_be or bc_stall)) and not (fetch_fifo_empty or fetch_fifo_almost_empty) and not bp_pred_valid;
    P_pc_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_program_counter <= to_unsigned(0, ADDR_WIDTH); 
            else
                if cdb_branch_mispredicted = '1' then
                    if cdb_in.branch_taken = '1' then
                        R_program_counter <= unsigned(cdb_in.branch_target_addr);
                    else
                        R_program_counter <= cdb_in.pc + 4;
                    end if;
                elsif bp_pred_valid = '1' then
                    R_program_counter <= bp_pred_target_pc;
                elsif bus_resp.ready = '1' and fetch_fifo_full = '0' and fetch_fifo_almost_full = '0' then
                    R_program_counter <= R_program_counter + 4;
                end if;
            end if;
        end if;
    end process;

    bus_req.address <= std_logic_vector(R_program_counter);
    bus_req.rw <= '0';
    bus_req.burst_len <= (others => '0');
    bus_req.data_size <= "10";
    bus_req.is_unsigned <= '1';
    bus_req.cancel <= icache_cancel_all;
    bus_req.ready <= '1';
    bus_req.valid <= not reset and not (fetch_fifo_full or fetch_fifo_almost_full) and not cdb_branch_mispredicted and not icache_cancel_all;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_fifo_pipeline.valid <= '0';
            else
                if cdb_branch_mispredicted = '1' then
                    R_fifo_pipeline.valid <= '0';
                elsif fetch_fifo_get_en = '1' then
                    R_fifo_pipeline.data <= fetch_fifo_instruction_read;
                    R_fifo_pipeline.valid <= '1';
                elsif stall_be /= '1' and bc_stall /= '1' then
                    R_fifo_pipeline.valid <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- ===================================
    --      INSTRUCTION DECODE LOGIC
    -- ===================================
    I_instr_dec : entity work.instruction_decoder
    port map(instruction            => R_fifo_pipeline.data(31 downto 0),
             instruction_valid      => R_fifo_pipeline.valid and not bc_stall and not stall_be,
             pc                     => unsigned(R_fifo_pipeline.data(63 downto 32)),
             invalid_instruction    => open,
             decoded_uop            => instdec_uop);

    I_branch_controller : entity work.branch_controller
    generic map(BRANCHING_DEPTH => MAX_SPEC_BRANCHES)
    port map(clk                    => clk,
             reset                  => reset,
             cdb_in                 => cdb_in,
             uop_in                 => instdec_uop,
             stall_in               => stall_be,
             stall_out              => bc_stall,
             free_branch_mask       => bc_free_branch_mask,
             active_branches_mask   => bc_spec_branches_mask);

    I_branch_predictor: entity work.branch_predictor
    port map(clk => clk,
             uop_in => instdec_uop,
             cdb_in => cdb_in,
             branch_predictor_taken => bp_pred_taken,
             branch_predictor_target_pc => bp_pred_target_pc);

    process(instdec_uop, bc_free_branch_mask, bc_spec_branches_mask, bp_pred_target_pc, bp_pred_taken)
    begin
        uop_out <= instdec_uop;
        uop_out.branch_pred_taken <= bp_pred_taken;
        uop_out.branch_pred_target <= std_logic_vector(bp_pred_target_pc);
        uop_out.branch_mask <= bc_free_branch_mask;
        uop_out.spec_branch_mask <= bc_spec_branches_mask;
    end process;
    
end rtl;
