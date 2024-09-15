library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

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
    signal cdb_request_lsu : std_logic;
    signal cdb_granted_lsu : std_logic;
    signal cdb_request_eu0 : std_logic;
    signal cdb_granted_eu0 : std_logic;
    signal cdb_out_eu0 : T_uop;
    signal cdb_out_lsu : T_uop;

    signal agu_temp : T_lsu_agu_port;

    signal lsu_in_port : T_lsu_in_port;
    signal lsu_out_port : T_lsu_out_port;
    signal rr_in_port : T_rr_in_port;
    signal rr_out_port : T_rr_out_port;
    signal rob_in_port : T_rob_in_port;
    signal rob_out_port : T_rob_out_port;
    signal rf_in_port : T_rf_in_port;
    signal rf_out_port : T_rf_out_port;
    signal sched_out_port : T_uop;

    signal uop_rr_out : T_uop;
    signal uop_sched_out : T_uop;
    signal pipeline_1_next : T_uop;
    signal R_pipeline_1 : T_uop;
    signal pipeline_3_next : T_uop;
    signal R_pipeline_3 : T_uop;
    signal pipeline_4_next : T_uop;
    signal R_pipeline_4 : T_uop;

    signal rob_retired_uop : T_rob;
    signal rob_retired_uop_valid : std_logic;

    signal pipeline_0_stall : std_logic;
    signal pipeline_1_stall : std_logic;
    signal pipeline_2_stall : std_logic;
    signal pipeline_3_stall : std_logic;
    signal pipeline_4_stall : std_logic;

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
    lsu_in_port.funct <= uop_rr_out.funct;
    lsu_in_port.phys_dst_reg <= uop_rr_out.phys_dst_reg;
    lsu_in_port.branch_mask <= uop_rr_out.branch_mask;
    lsu_in_port.valid <= uop_rr_out.valid;

    agu_temp.address <= (others => '0');
    agu_temp.address_valid <= '0';
    agu_temp.data <= (others => '0');
    agu_temp.data_valid <= '0';
    agu_temp.rw <= '0';
    agu_temp.sq_tag <= (others => '0');
    agu_temp.lq_tag <= (others => '0');

    lsu_inst : entity work.load_store_unit_to
    port map(lsu_in_port    => lsu_in_port,
             lsu_out_port   => lsu_out_port,
             cdb_in         => cdb,
             cdb_out        => cdb_out_lsu,
             cdb_request    => cdb_request_lsu,
             cdb_granted    => cdb_granted_lsu,
             agu_in_port    => agu_temp,
             bus_req        => bus_req,
             bus_resp       => bus_resp,
             bus_ready      => bus_ready,
             stall_in       => R_pipeline_1.valid and pipeline_2_stall,
             stall_out      => lsu_stall_out,
             clk            => clk,
             reset          => reset);
    
    rob_in_port.arch_dst_reg <= uop_rr_out.arch_dst_reg;
    rob_in_port.phys_dst_reg <= uop_rr_out.phys_dst_reg;
    rob_in_port.branch_mask <= uop_rr_out.branch_mask;
    rob_in_port.valid <= uop_rr_out.valid;

    reorder_buffer_inst : entity work.reorder_buffer
    port map(rob_in_port        => rob_in_port,
             rob_out_port       => rob_out_port,
             cdb                => cdb,
             retired_uop        => rob_retired_uop,
             retired_uop_valid  => rob_retired_uop_valid,
             stall_in           => R_pipeline_1.valid and pipeline_2_stall,
             stall_out          => rob_stall_out,
             clk                => clk,
             reset              => reset);

    P_pipeline_1_next : process(uop_rr_out, rob_out_port, lsu_out_port)
    begin
        pipeline_1_next <= uop_rr_out;
        pipeline_1_next.id <= rob_out_port.id;
        pipeline_1_next.sq_index <= lsu_out_port.sq_index;
        pipeline_1_next.lq_index <= lsu_out_port.lq_index;
    end process;

    P_pipeline_1 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_1.valid <= '0';
            else
                R_pipeline_1 <= F_pipeline_reg_logic(pipeline_1_next, R_pipeline_1, cdb, pipeline_2_stall);
            end if;
        end if;
    end process;

    pipeline_1_stall <= (R_pipeline_1.valid and pipeline_2_stall) or rob_stall_out or lsu_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 2
    -- ===========================================
    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => 8)
    port map(uop_in            => R_pipeline_1,
             uop_out           => uop_sched_out,
             cdb_in            => cdb,
             stall_in          => pipeline_3_stall,
             stall_out         => sched_stall_out,
             clk               => clk,
             reset             => reset);

    
    
    pipeline_2_stall <= sched_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 3
    -- ===========================================
    rf_in_port.phys_src_reg_1 <= uop_sched_out.phys_src_reg_1;
    rf_in_port.phys_src_reg_2 <= uop_sched_out.phys_src_reg_2;
    rf_in_port.valid <= uop_sched_out.valid;
    
    regfile_inst : entity work.register_file
    port map(rf_in_port   => rf_in_port,
             rf_out_port  => rf_out_port,
             cdb        => cdb,
             stall_in   => R_pipeline_3.valid and pipeline_4_stall,
             stall_out  => rf_stall_out,
             clk        => clk,
             reset      => reset);

    P_pipeline_3_next : process(uop_sched_out, rf_out_port)
    begin
        pipeline_3_next <= uop_sched_out;
        pipeline_3_next.reg_read_1_data <= rf_out_port.reg_data_1;
        pipeline_3_next.reg_read_2_data <= rf_out_port.reg_data_2;
    end process;

    P_pipeline_3 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_3.valid <= '0';
            else
                R_pipeline_3 <= F_pipeline_reg_logic(pipeline_3_next, R_pipeline_3, cdb, pipeline_4_stall);
            end if;
        end if;
    end process;

    pipeline_3_stall <= (R_pipeline_3.valid and pipeline_4_stall) or rf_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 4
    -- ===========================================
    eu0_inst : entity work.execution_unit
    port map(eu_in_port     => R_pipeline_3,
             eu_out_port    => cdb_out_eu0,
             stall_in       => eu0_stall_in,
             stall_out      => eu0_stall_out,
             clk            => clk,
             reset          => reset);

    P_pipeline_4 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_4.valid <= '0';
            else
                R_pipeline_4 <= F_pipeline_reg_logic(pipeline_4_next, R_pipeline_4, cdb, '0');
            end if;
        end if;
    end process;

    pipeline_4_stall <= '0'; 
    cdb <= R_pipeline_4;
    
    process(cdb_request_lsu, cdb_out_lsu, cdb_out_eu0)
    begin
        eu0_stall_in <= '1';
        pipeline_4_next <= UOP_ZERO;
        if cdb_out_lsu.valid = '1' then
            pipeline_4_next <= cdb_out_lsu;
        elsif cdb_out_eu0.valid = '1' then
            eu0_stall_in <= '0';
            pipeline_4_next <= cdb_out_eu0;
        end if;
    end process;
    
end rtl;
