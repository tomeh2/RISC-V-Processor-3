library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity back_end is
    port(
        -- uOP from decoder
        uop_1       : in T_uop;

        -- CDB
        cdb_out     : out T_uop;

        -- Flow control
        stall_be    : out std_logic;

        -- External bus / cache signals
        bus_req     : out T_bus_request;
        bus_resp    : in T_bus_response;

        clk         : in std_logic;
        reset       : in std_logic
    );
end back_end;

architecture rtl of back_end is
    -- Pipeline registers
    signal R_pipeline_0: T_uop;
    signal pipeline_0_stall: std_logic;

    signal R_pipeline_1: T_uop;
    signal pipeline_1_next: T_uop;
    signal pipeline_1_stall: std_logic;

    signal R_pipeline_2: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_2_stall: std_logic;

    signal R_pipeline_3: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_3_next: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_3_stall: std_logic_vector(SCHED_PORTS - 1 downto 0);

    signal R_pipeline_4: T_uop;
    signal pipeline_4_stall: std_logic_vector(0 to SCHED_PORTS - 1);

    -- Register Rename
    signal rr_uop_out: T_uop;
    signal rr_stall_out: std_logic;

    -- Scheduler
    signal sched_uop_out_port: T_uop_array(0 to SCHED_PORTS - 1);
    signal sched_port_stall: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal sched_stall_in: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal sched_stall_out: std_logic;

    -- Register File
    signal rf_uop_out: T_uop_array(0 to SCHED_PORTS - 1);
    signal rf_stall_in: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal rf_stall_out: std_logic_vector(SCHED_PORTS - 1 downto 0);

    -- CSR Registers
    signal csr_value: std_logic_vector(31 downto 0);
    signal csr_stall_in: std_logic;
    signal csr_stall_out: std_logic;

    -- Execution Unit 0
    signal eu0_uop_out: T_uop;
    signal eu0_stall_in: std_logic;
    signal eu0_stall_out: std_logic;

    -- Address Generation Unit
    signal agu_temp : T_lsu_agu_port;

    -- Reorder Buffer
    signal rob_allocated_id: unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal rob_retired_uop: T_retired_uop;
    signal rob_stall_out: std_logic;

    -- Load Store Unit
    signal lsu_uop_in: T_uop;
    signal lsu_allocated_sq: unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal lsu_allocated_lq: unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal lsu_stall_out: std_logic;
    signal lsu_cdb_req: std_logic;

    -- Debug
    signal rat_debug: T_rr_debug;

    -- Common Data Bus (CDB)
    signal cdb_granted_lsu: std_logic;
    signal cdb_granted_eu0: std_logic;
    signal cdb_out_eu0: T_uop;
    signal cdb_out_lsu: T_uop;
    signal cdb: T_uop;
begin
    stall_be <= pipeline_0_stall;

    -- ===========================================
    --             PIPELINE STAGE 0
    -- ===========================================
    pipeline_0_stall <= rr_stall_out;

    register_rename_inst : entity work.register_rename
    port map(uop_in                 => uop_1,
             uop_out                => rr_uop_out,
             cdb_in                 => cdb,
             retired_uop            => rob_retired_uop,
             stall_in               => pipeline_1_stall and R_pipeline_0.valid,
             stall_out              => rr_stall_out,
             debug_out              => rat_debug,
             clk                    => clk,
             reset                  => reset);

    process(clk)
    begin
        F_pipeline_reg(rr_uop_out, R_pipeline_0, cdb, clk, reset, pipeline_1_stall);
    end process;
    -- ===========================================
    --             PIPELINE STAGE 1
    -- ===========================================
    pipeline_1_stall <= rob_stall_out or lsu_stall_out or (R_pipeline_1.valid and pipeline_2_stall);

    reorder_buffer_inst : entity work.reorder_buffer
    port map(uop_in             => rr_uop_out,
             uop_allocated_id   => rob_allocated_id,
             cdb                => cdb,
             retired_uop        => rob_retired_uop,
             stall_in           => (R_pipeline_1.valid and sched_stall_out) or lsu_stall_out,
             stall_out          => rob_stall_out,
             clk                => clk,
             reset              => reset);

    process(rob_allocated_id, rr_uop_out)
    begin
        lsu_uop_in <= rr_uop_out;
        lsu_uop_in.id <= rob_allocated_id;
    end process;

    P_pipeline_1_next : process(rr_uop_out, rob_allocated_id, lsu_allocated_sq, lsu_allocated_lq)
    begin
        pipeline_1_next <= rr_uop_out;
        pipeline_1_next.id <= rob_allocated_id;
        pipeline_1_next.sq_index <= lsu_allocated_sq;
        pipeline_1_next.lq_index <= lsu_allocated_lq;
    end process;

    process(clk)
    begin
        F_pipeline_reg(pipeline_1_next, R_pipeline_1, cdb, clk, reset, pipeline_2_stall);
    end process;
    -- ===========================================
    --             PIPELINE STAGE 2
    -- ===========================================
    pipeline_2_stall <= sched_stall_out;

    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => SCHED_ENTRIES,
                NUM_OUTPUT_PORT => SCHED_PORTS,
                OUTPUT_PORT_EXEC_IDS => (0, 1, 2, 3, 4, 5, 6, 7))
    port map(uop_in            => R_pipeline_1,
             uop_out           => sched_uop_out_port,
             cdb_in            => cdb,
             stall_in          => sched_stall_in,
             stall_out         => sched_stall_out,
             clk               => clk,
             reset             => reset);

    G_pipeline_2 : for i in 0 to SCHED_PORTS - 1 generate
        process(clk)
        begin
            F_pipeline_reg(sched_uop_out_port(i), R_pipeline_2(i), cdb, clk, reset, pipeline_3_stall(i));
        end process;
        sched_stall_in(i) <= pipeline_3_stall(i) and R_pipeline_2(i).valid;
    end generate;
    -- ===========================================
    --             PIPELINE STAGE 3
    -- ===========================================
    pipeline_3_stall <= rf_stall_out or csr_stall_out;

    regfile_inst : entity work.register_file
    generic map(NUM_PORTS => 2)
    port map(uop_in         => R_pipeline_2,
             uop_out        => rf_uop_out,
             cdb_in         => cdb,
             stall_in       => rf_stall_in,
             stall_out      => rf_stall_out,
             debug_rat_in   => rat_debug,
             clk            => clk,
             reset          => reset);

    G_csr_regs: if CSR_ENABLE = true generate
        I_csr_regs: entity work.csr
        port map(uop_in         => R_pipeline_2(0),
                 csr_value      => csr_value,
                 retired_uop_in => rob_retired_uop,
                 cdb_in         => cdb,
                 stall_in       => csr_stall_in,
                 stall_out      => csr_stall_out,
                 clk            => clk,
                 reset          => reset);
    end generate;

    process(rf_uop_out, R_pipeline_2(0).funct, csr_value)
    begin
        pipeline_3_next <= rf_uop_out;

        if CSR_ENABLE = true then
            if R_pipeline_2(0).funct(6 downto 4) /= "000" then
                pipeline_3_next(0).reg_read_2_data <= csr_value;
            end if;
        end if;
    end process;

    G_pipeline_3 : for i in 0 to SCHED_PORTS - 1 generate
        process(clk)
        begin
            F_pipeline_reg(pipeline_3_next(i), R_pipeline_3(i), cdb, clk, reset, pipeline_4_stall(i));
        end process;
        rf_stall_in(i) <= pipeline_4_stall(i) and R_pipeline_3(i).valid;
        csr_stall_in <= pipeline_4_stall(0) and R_pipeline_3(0).valid;
    end generate;
    -- ===========================================
    --             PIPELINE STAGE 4
    -- ===========================================
    pipeline_4_stall(0) <= eu0_stall_out;
    pipeline_4_stall(1) <= '0';

    agu_inst : entity work.address_generation_unit
    port map(uop_in => R_pipeline_3(1),
             agu_out => agu_temp,
             clk => clk,
             reset => reset);
    
    eu0_inst : entity work.execution_unit
    port map(uop_in         => R_pipeline_3(0),
             uop_out        => eu0_uop_out,
             cdb_in         => cdb,
             stall_in       => eu0_stall_in and R_pipeline_4.valid,
             stall_out      => eu0_stall_out,
             clk            => clk,
             reset          => reset);

    process(clk)
    begin
        F_pipeline_reg(eu0_uop_out, R_pipeline_4, cdb, clk, reset, eu0_stall_in);
    end process;

    process(R_pipeline_4, cdb_out_lsu, lsu_cdb_req)
    begin
        eu0_stall_in <= '1';
        cdb_granted_lsu <= '0';
        cdb <= UOP_ZERO;
        if lsu_cdb_req = '1' then
            cdb_granted_lsu <= '1';
            cdb <= cdb_out_lsu;
        elsif R_pipeline_4.valid = '1' then
            eu0_stall_in <= '0';
            cdb <= R_pipeline_4;
        end if;
    end process;
    
    -- ===========================================
    --             LOAD-STORE UNIT
    -- ===========================================
    lsu_inst : entity work.load_store_unit_to
    port map(uop_in             => lsu_uop_in,
             uop_allocated_sq   => lsu_allocated_sq,
             uop_allocated_lq   => lsu_allocated_lq,
             cdb_in             => cdb,
             cdb_out            => cdb_out_lsu,
             cdb_request        => lsu_cdb_req,
             cdb_granted        => cdb_granted_lsu,
             retired_uop        => rob_retired_uop,
             agu_in_port        => agu_temp,
             bus_req            => bus_req,
             bus_resp           => bus_resp,
             stall_in           => (R_pipeline_1.valid and sched_stall_out) or rob_stall_out,
             stall_out          => lsu_stall_out,
             clk                => clk,
             reset              => reset);

    cdb_out <= cdb;
end rtl;
