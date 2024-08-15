library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity back_end is
    port(
        uop_1   : in T_uop;

        clk     : in std_logic;
        reset   : in std_logic
    );
end back_end;

architecture rtl of back_end is
    signal rr_in_port : T_rr_in_port;
    signal rr_out_port : T_rr_out_port;
    signal rob_in_port : T_rob_in_port;
    signal rob_out_port : T_rob_out_port;
    signal rf_in_port : T_rf_in_port;
    signal rf_out_port : T_rf_out_port;
    signal sched_out_port : T_uop;

    signal pipeline_0_next : T_uop;
    signal R_pipeline_0 : T_uop;
    signal pipeline_1_next : T_uop;
    signal R_pipeline_1 : T_uop;
    signal pipeline_2_next : T_uop;
    signal R_pipeline_2 : T_uop;
    signal pipeline_3_next : T_uop;
    signal R_pipeline_3 : T_uop;
    signal pipeline_4_next : T_uop;
    signal R_pipeline_4 : T_uop;
    signal R_cdb_eu0 : T_uop;

    signal rob_retired_uop : T_rob;
    signal rob_retired_uop_valid : std_logic;

    signal pipeline_0_stall : std_logic;
    signal pipeline_1_stall : std_logic;
    signal pipeline_2_stall : std_logic;
    signal pipeline_3_stall : std_logic;
    signal pipeline_4_stall : std_logic;

    signal eu0_stall_out : std_logic;
    signal rf_stall_out : std_logic;
    signal sched_stall_out : std_logic;
    signal rr_stall_out : std_logic;
    signal rob_stall_out : std_logic;

    signal cdb : T_uop;
begin
    -- TODO: ADD BLOCK STALL SIGNALS INTO LOGIC

    -- ===========================================
    --             PIPELINE STAGE 0
    -- ===========================================
    rr_in_port.arch_src_reg_1 <= uop_1.arch_src_reg_1;
    rr_in_port.arch_src_reg_2 <= uop_1.arch_src_reg_2;
    rr_in_port.arch_dst_reg <= uop_1.arch_dst_reg;
    rr_in_port.branch_mask <= uop_1.branch_mask;
    rr_in_port.valid <= uop_1.valid;

    register_rename_inst : entity work.register_rename
    port map(rr_in_port             => rr_in_port,
             rr_out_port            => rr_out_port,
             cdb                    => cdb,
             stall_in               => R_pipeline_0.valid and pipeline_1_stall,
             stall_out              => rr_stall_out,
             clk                    => clk,
             reset                  => reset);
             
    P_pipeline_0_next : process(uop_1, rr_out_port)
    begin
        pipeline_0_next <= uop_1;
        pipeline_0_next.phys_dst_reg <= rr_out_port.phys_dst_reg;
        pipeline_0_next.phys_src_reg_1 <= rr_out_port.phys_src_reg_1;
        pipeline_0_next.phys_src_reg_2 <= rr_out_port.phys_src_reg_2;
    end process;

    P_pipeline_0 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_0.valid <= '0';
            else
                R_pipeline_0 <= F_pipeline_reg_logic(pipeline_0_next, R_pipeline_0, cdb, pipeline_1_stall);
            end if;
        end if;
    end process;

    pipeline_0_stall <= (R_pipeline_0.valid and pipeline_1_stall) or rr_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 1
    -- ===========================================
    rob_in_port.arch_dst_reg <= R_pipeline_0.arch_dst_reg;
    rob_in_port.phys_dst_reg <= R_pipeline_0.phys_dst_reg;
    rob_in_port.branch_mask <= R_pipeline_0.branch_mask;
    rob_in_port.valid <= R_pipeline_0.valid;

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

    P_pipeline_1_next : process(R_pipeline_0, rob_out_port)
    begin
        pipeline_1_next <= R_pipeline_0;
        pipeline_1_next.id <= rob_out_port.id;
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

    pipeline_1_stall <= (R_pipeline_1.valid and pipeline_2_stall) or rob_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 2
    -- ===========================================
    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => 8)
    port map(sched_in_port     => R_pipeline_1,
             sched_out_port    => pipeline_2_next,
             cdb               => cdb,
             stall_in          => R_pipeline_2.valid and pipeline_3_stall,
             stall_out         => sched_stall_out,
             clk               => clk,
             reset             => reset);

    P_pipeline_2 : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_pipeline_2.valid <= '0';
            else
                R_pipeline_2 <= F_pipeline_reg_logic(pipeline_2_next, R_pipeline_2, cdb, pipeline_3_stall);
            end if;
        end if;
    end process;
    
    pipeline_2_stall <= sched_stall_out;
    -- ===========================================
    --             PIPELINE STAGE 3
    -- ===========================================
    rf_in_port.phys_src_reg_1 <= R_pipeline_2.phys_src_reg_1;
    rf_in_port.phys_src_reg_2 <= R_pipeline_2.phys_src_reg_2;
    rf_in_port.valid <= R_pipeline_2.valid;
    
    regfile_inst : entity work.register_file
    port map(rf_in_port   => rf_in_port,
             rf_out_port  => rf_out_port,
             cdb        => cdb,
             stall_in   => R_pipeline_3.valid and pipeline_4_stall,
             stall_out  => rf_stall_out,
             clk        => clk,
             reset      => reset);

    P_pipeline_3_next : process(R_pipeline_2, rf_out_port)
    begin
        pipeline_3_next <= R_pipeline_2;
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
    port map(uop        => R_pipeline_3,
             cdb        => pipeline_4_next,
             stall_in   => '0',
             stall_out  => eu0_stall_out,
             clk        => clk,
             reset      => reset);

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

--    lsu_inst : entity work.load_store_unit_to
--    port map(uop_in         => ,
--             sq_index       => ,
--             lq_index       => ,
--             cdb_in         => ,
--             cdb_out        => ,
--             cdb_request    => ,
--             cdb_granted    => ,
--             agu_port       => ,
--             bus_req        => ,
--             bus_resp       => ,
--             bus_ready      => ,
--             stall_in       => ,
--             stall_out      => ,
--             clk            => ,
--             reset          => );
    cdb <= R_cdb_eu0;
end rtl;
