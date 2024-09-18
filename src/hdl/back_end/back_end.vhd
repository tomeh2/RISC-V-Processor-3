library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity back_end is
    port(
        -- uOP from decoder
        uop_1       : in T_uop;

        -- Flow control
        stall_be    : out std_logic;

        -- External bus / cache signals
        bus_req     : out T_bus_request;
        bus_resp    : in T_bus_response;
        bus_ready   : in std_logic;

        clk         : in std_logic;
        reset       : in std_logic
    );
end back_end;

architecture rtl of back_end is
    signal cdb_granted_lsu : std_logic;
    signal cdb_granted_eu0 : std_logic;
    signal cdb_out_eu0 : T_uop;
    signal cdb_out_lsu : T_uop;

    signal agu_temp : T_lsu_agu_port;
    
    signal rob_allocated_id : unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal lsu_allocated_sq : unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal lsu_allocated_lq : unsigned(LQ_TAG_WIDTH - 1 downto 0);

    signal uop_rr_out : T_uop;
    signal uop_sched_out : T_uop;
    signal uop_rf_out : T_uop;
    signal eu0_out : T_uop;
    signal pipeline_1_next : T_uop;
    signal R_pipeline_1 : T_uop;

    signal rob_retired_uop : T_rob;
    signal rob_retired_uop_valid : std_logic;

    signal pipeline_1_stall : std_logic;

    signal eu0_stall_in : std_logic;
    signal eu0_stall_out : std_logic;
    signal rf_stall_out : std_logic;
    signal sched_stall_out : std_logic;
    signal rr_stall_out : std_logic;
    signal rob_stall_out : std_logic;
    signal lsu_stall_out : std_logic;

    signal cdb : T_uop;
begin
    stall_be <= rr_stall_out;

    -- ===========================================
    --             PIPELINE STAGE 0
    -- ===========================================
    register_rename_inst : entity work.register_rename
    port map(uop_in                 => uop_1,
             uop_out                => uop_rr_out,
             cdb_in                 => cdb,
             stall_in               => pipeline_1_stall,
             stall_out              => rr_stall_out,
             clk                    => clk,
             reset                  => reset);
    -- ===========================================
    --             PIPELINE STAGE 1
    -- ===========================================
    agu_temp.address <= (others => '0');
    agu_temp.address_valid <= '0';
    agu_temp.data <= (others => '0');
    agu_temp.data_valid <= '0';
    agu_temp.rw <= '0';
    agu_temp.sq_tag <= (others => '0');
    agu_temp.lq_tag <= (others => '0');

    reorder_buffer_inst : entity work.reorder_buffer
    port map(uop_in             => uop_rr_out,
             uop_allocated_id   => rob_allocated_id,
             cdb                => cdb,
             retired_uop        => rob_retired_uop,
             retired_uop_valid  => rob_retired_uop_valid,
             stall_in           => R_pipeline_1.valid and sched_stall_out,
             stall_out          => rob_stall_out,
             clk                => clk,
             reset              => reset);

    P_pipeline_1_next : process(uop_rr_out, rob_allocated_id, lsu_allocated_sq, lsu_allocated_lq)
    begin
        pipeline_1_next <= uop_rr_out;
        pipeline_1_next.id <= rob_allocated_id;
        pipeline_1_next.sq_index <= lsu_allocated_sq;
        pipeline_1_next.lq_index <= lsu_allocated_lq;
    end process;

    P_pipeline_1 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_1.valid <= '0';
            else
                R_pipeline_1 <= F_pipeline_reg_logic(pipeline_1_next, R_pipeline_1, cdb, sched_stall_out);
            end if;
        end if;
    end process;
    pipeline_1_stall <= rob_stall_out or lsu_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 2
    -- ===========================================
    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => 8)
    port map(uop_in            => R_pipeline_1,
             uop_out           => uop_sched_out,
             cdb_in            => cdb,
             stall_in          => rf_stall_out,
             stall_out         => sched_stall_out,
             clk               => clk,
             reset             => reset);
    -- ===========================================
    --             PIPELINE STAGE 3
    -- ===========================================
    regfile_inst : entity work.register_file
    port map(uop_in     => uop_sched_out,
             uop_out    => uop_rf_out,
             cdb_in     => cdb,
             stall_in   => eu0_stall_out,
             stall_out  => rf_stall_out,
             clk        => clk,
             reset      => reset);
    -- ===========================================
    --             PIPELINE STAGE 4
    -- ===========================================
    eu0_inst : entity work.execution_unit
    port map(uop_in         => uop_rf_out,
             uop_out        => eu0_out,
             cdb_in         => cdb,
             stall_in       => eu0_stall_in,
             stall_out      => eu0_stall_out,
             clk            => clk,
             reset          => reset);
    
    process(eu0_out, cdb_out_lsu)
    begin
        eu0_stall_in <= '1';
        cdb <= UOP_ZERO;
        if cdb_out_lsu.valid = '1' then
            cdb <= cdb_out_lsu;
        elsif eu0_out.valid = '1' then
            eu0_stall_in <= '0';
            cdb <= eu0_out;
        end if;
    end process;
    
    -- ===========================================
    --             LOAD-STORE UNIT
    -- ===========================================
    lsu_inst : entity work.load_store_unit_to
    port map(uop_in             => uop_rr_out,
             uop_allocated_sq   => lsu_allocated_sq,
             uop_allocated_lq   => lsu_allocated_lq,
             cdb_in             => cdb,
             cdb_out            => cdb_out_lsu,
             cdb_request        => open,
             cdb_granted        => cdb_granted_lsu,
             agu_in_port        => agu_temp,
             bus_req            => bus_req,
             bus_resp           => bus_resp,
             bus_ready          => bus_ready,
             stall_in           => R_pipeline_1.valid and sched_stall_out,
             stall_out          => lsu_stall_out,
             clk                => clk,
             reset              => reset);
    
end rtl;
