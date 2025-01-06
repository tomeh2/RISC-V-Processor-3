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
    signal pipeline_0_next: T_uop;
    signal pipeline_0_stall: std_logic;
    signal pipeline_0_ready: std_logic;

    signal R_pipeline_1: T_uop;
    signal pipeline_1_next: T_uop;
    signal pipeline_1_stall: std_logic;
    signal pipeline_1_ready: std_logic;

    signal R_pipeline_2: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_2_stall: std_logic;
    signal pipeline_2_ready: std_logic;

    signal R_pipeline_3: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_3_next: T_uop_array(0 to SCHED_PORTS - 1);
    signal pipeline_3_stall: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal pipeline_3_ready: std_logic_vector(SCHED_PORTS - 1 downto 0);

    signal R_pipeline_4: T_uop;
    signal pipeline_4_stall: std_logic_vector(0 to SCHED_PORTS - 1);
    signal pipeline_4_ready: std_logic_vector(0 to SCHED_PORTS - 1);

    signal R_pipeline_5: T_uop;
    signal pipeline_5_stall: std_logic_vector(0 to SCHED_PORTS - 1);

    -- Register Rename
    signal rr_uop_out: T_uop;
    signal rr_stall: std_logic;
    signal rr_ready: std_logic;

    -- Scheduler
    signal sched_uop_out_port: T_uop_array(0 to SCHED_PORTS - 1);
    signal sched_port_stall: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal sched_stall: std_logic_vector(SCHED_PORTS - 1 downto 0);
    signal sched_ready: std_logic;

    -- Register File
    signal rf_uop_out: T_uop_array(0 to SCHED_PORTS - 1);

    -- CSR Registers
    signal csr_value: std_logic_vector(31 downto 0);

    -- Execution Unit 0
    signal eu0_uop_out: T_uop;
    signal eu0_ready: std_logic;

    -- Address Generation Unit
    signal agu_temp : T_lsu_agu_port;

    -- Reorder Buffer
    signal rob_allocated_id: unsigned(UOP_INDEX_WIDTH - 1 downto 0);
    signal rob_retired_uop: T_retired_uop;
    signal rob_stall: std_logic;
    signal rob_ready: std_logic;

    -- Load Store Unit
    signal lsu_uop_in: T_uop;
    signal lsu_allocated_sq: unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal lsu_allocated_lq: unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal lsu_stall_out: std_logic;

    -- Debug
    signal rat_debug: T_rr_debug;

    -- Common Data Bus (CDB)
    signal cdb_requests: std_logic_vector(1 downto 0);
    signal cdb_grants: std_logic_vector(1 downto 0);
    signal cdb_ports: T_uop_array(0 to 1);
    signal cdb: T_uop;
begin
    stall_be <= pipeline_0_stall;

    -- ===========================================
    --             PIPELINE STAGE 0
    -- ===========================================
    pipeline_0_stall <= not rr_ready or (R_pipeline_0.valid and pipeline_1_stall);

    register_rename_inst : entity work.register_rename
    port map(uop_in                 => uop_1,
             uop_out                => rr_uop_out,
             cdb_in                 => cdb,
             retired_uop            => rob_retired_uop,
             stall                  => pipeline_0_stall,
             ready                  => rr_ready,
             debug_out              => rat_debug,
             clk                    => clk,
             reset                  => reset);

    process(rr_uop_out, rr_ready)
    begin
        pipeline_0_next <= rr_uop_out;
    end process;

    pipeline_0_ready <= rr_ready;
    process(clk)
    begin
        F_pipeline_reg(pipeline_0_next, R_pipeline_0, cdb, clk, reset, pipeline_1_stall, pipeline_0_ready);
    end process;
    -- ===========================================
    --             PIPELINE STAGE 1
    -- ===========================================
    pipeline_1_stall <= not rob_ready or lsu_stall_out or (R_pipeline_1.valid and pipeline_2_stall);

    reorder_buffer_inst : entity work.reorder_buffer
    port map(uop_in             => R_pipeline_0,
             uop_allocated_id   => rob_allocated_id,
             cdb                => cdb,
             retired_uop        => rob_retired_uop,
             stall              => pipeline_1_stall,
             ready              => rob_ready,
             clk                => clk,
             reset              => reset);

    process(rob_allocated_id, R_pipeline_0)
    begin
        lsu_uop_in <= R_pipeline_0;
        lsu_uop_in.id <= rob_allocated_id;
    end process;

    P_pipeline_1_next : process(R_pipeline_0, rob_allocated_id, lsu_allocated_sq, lsu_allocated_lq, rob_ready, lsu_stall_out)
    begin
        pipeline_1_next <= R_pipeline_0;
        pipeline_1_next.id <= rob_allocated_id;
        pipeline_1_next.sq_index <= lsu_allocated_sq;
        pipeline_1_next.lq_index <= lsu_allocated_lq;
        --pipeline_1_next.valid <= R_pipeline_0.valid and rob_ready and not lsu_stall_out;
    end process;

    pipeline_1_ready <= rob_ready and not lsu_stall_out;
    process(clk)
    begin
        F_pipeline_reg(pipeline_1_next, R_pipeline_1, cdb, clk, reset, pipeline_2_stall, pipeline_1_ready);
    end process;
    -- ===========================================
    --             PIPELINE STAGE 2
    -- ===========================================
    pipeline_2_stall <= not sched_ready;

    scheduler_inst : entity work.scheduler
    generic map(ENTRIES => SCHED_ENTRIES,
                NUM_OUTPUT_PORT => SCHED_PORTS,
                OUTPUT_PORT_EXEC_IDS => (0, 1, 2, 3, 4, 5, 6, 7))
    port map(uop_in            => R_pipeline_1,
             uop_out           => sched_uop_out_port,
             cdb_in            => cdb,
             stall             => sched_stall,
             ready             => sched_ready,
             clk               => clk,
             reset             => reset);

    pipeline_2_ready <= '1';
    G_pipeline_2 : for i in 0 to SCHED_PORTS - 1 generate
        process(clk)
        begin
            F_pipeline_reg(sched_uop_out_port(i), R_pipeline_2(i), cdb, clk, reset, pipeline_3_stall(i), pipeline_2_ready);
        end process;
        sched_stall(i) <= pipeline_3_stall(i) and R_pipeline_2(i).valid;
    end generate;
    -- ===========================================
    --             PIPELINE STAGE 3
    -- ===========================================
    process(R_pipeline_3, pipeline_4_stall)
    begin
        for i in 0 to SCHED_PORTS - 1 loop
            pipeline_3_stall(i) <= R_pipeline_3(i).valid and pipeline_4_stall(i);
        end loop;
    end process;

    regfile_inst : entity work.register_file
    generic map(NUM_PORTS => 2)
    port map(uop_in         => R_pipeline_2,
             uop_out        => rf_uop_out,
             cdb_in         => cdb,
             debug_rat_in   => rat_debug,
             clk            => clk,
             reset          => reset);

    G_csr_regs: if CSR_ENABLE = true generate
        I_csr_regs: entity work.csr
        port map(uop_in         => R_pipeline_2(0),
                 csr_value      => csr_value,
                 retired_uop_in => rob_retired_uop,
                 cdb_in         => cdb,
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

    pipeline_3_ready <= (others => '1');
    G_pipeline_3 : for i in 0 to SCHED_PORTS - 1 generate
        process(clk)
        begin
            F_pipeline_reg(pipeline_3_next(i), R_pipeline_3(i), cdb, clk, reset, pipeline_4_stall(i), pipeline_3_ready(i));
        end process;
    end generate;
    -- ===========================================
    --             PIPELINE STAGE 4
    -- ===========================================
    pipeline_4_stall(0) <= not eu0_ready or (R_pipeline_4.valid and pipeline_5_stall(0));
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
             stall          => pipeline_4_stall(0),
             ready          => eu0_ready,
             clk            => clk,
             reset          => reset);

    pipeline_4_ready(0) <= eu0_ready;
    pipeline_4_ready(1) <= '1';
    process(clk)
    begin
        F_pipeline_reg(eu0_uop_out, R_pipeline_4, cdb, clk, reset, pipeline_5_stall(0), pipeline_4_ready(0));
    end process;
    -- ===========================================
    --             PIPELINE STAGE 5
    -- ===========================================
    pipeline_5_stall(0) <= not cdb_grants(0);
    cdb_ports(0) <= R_pipeline_4;
    cdb_requests(0) <= R_pipeline_4.valid;

    process(R_pipeline_4, cdb_requests, cdb_ports)
        variable cdb_temp: T_uop;
        variable cdb_granted_temp: std_logic_vector(1 downto 0);
    begin
        cdb <= UOP_ZERO;
        cdb_temp := UOP_ZERO;
        cdb_granted_temp := (others => '0');
        for i in 0 to 1 loop
            if cdb_requests(i) = '1' then
                cdb_temp := cdb_ports(i);
                cdb_granted_temp := (others => '0');
                cdb_granted_temp(i) := '1';
            end if;
        end loop;
        cdb <= cdb_temp;
        cdb_grants <= cdb_granted_temp;
    end process;
    
    -- ===========================================
    --             LOAD-STORE UNIT
    -- ===========================================
    lsu_inst : entity work.load_store_unit_to
    port map(uop_in             => lsu_uop_in,
             uop_allocated_sq   => lsu_allocated_sq,
             uop_allocated_lq   => lsu_allocated_lq,
             cdb_in             => cdb,
             cdb_out            => cdb_ports(1),
             cdb_request        => cdb_requests(1),
             cdb_granted        => cdb_grants(1),
             retired_uop        => rob_retired_uop,
             agu_in_port        => agu_temp,
             bus_req            => bus_req,
             bus_resp           => bus_resp,
             stall_in           => (R_pipeline_1.valid and pipeline_2_stall) or not rob_ready,
             stall_out          => lsu_stall_out,
             clk                => clk,
             reset              => reset);

    cdb_out <= cdb;
end rtl;
