library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

-- This file implements a Load-Store Unit with Total Store Ordering(TSO).
-- Store instructions are executed in-order and only after they are retired.
-- Load instructions also happen in-order but don't need to retire beforehand.

entity load_store_unit_to is
    port(
        lsu_in_port     : in T_lsu_in_port;
        lsu_out_port    : out T_lsu_out_port;

        cdb_in          : in T_uop;
        cdb_out         : out T_uop;
        cdb_request     : out std_logic;
        cdb_granted     : in std_logic;

        agu_in_port     : in T_lsu_agu_port;

        bus_req         : out T_bus_request;
        bus_resp        : in T_bus_response;
        bus_ready       : in std_logic;

        stall_in        : in std_logic;
        stall_out       : out std_logic;

        clk             : in std_logic;
        reset           : in std_logic
    );
end load_store_unit_to;

architecture rtl of load_store_unit_to is
    type T_store_queue is array (0 to SQ_ENTRIES - 1) of T_lsu_store;
    signal M_store_queue : T_store_queue;

    -- STORE QUEUE CONTROL SIGNALS
    type T_sq_tail_snapshot is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal M_sq_tail_snapshot : T_sq_tail_snapshot;
    type T_sq_util_snapshot is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(SQ_TAG_WIDTH downto 0);
    signal M_sq_util_snapshot : T_sq_util_snapshot;
    
    signal R_sq_head : unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal R_sq_tail : unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal R_sq_util : unsigned(SQ_TAG_WIDTH downto 0);
    signal sq_head_next : unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal sq_tail_next : unsigned(SQ_TAG_WIDTH - 1 downto 0);
    signal sq_util_next : unsigned(SQ_TAG_WIDTH downto 0);

    signal sq_valid : std_logic_vector(SQ_ENTRIES - 1 downto 0);

    signal sq_head_uop : T_lsu_store;
    signal sq_dispatch_enable : std_logic;

    signal sq_full : std_logic;
    signal sq_empty : std_logic;

    signal sq_enqueue : std_logic;
    signal sq_dequeue : std_logic;
    
    -- LOAD QUEUE CONTROL SIGNALS
    constant STORE_MASK_ZERO : std_logic_vector(SQ_ENTRIES - 1 downto 0) := (others => '0');
    
    type T_load_queue is array (0 to LQ_ENTRIES - 1) of T_lsu_load;
    signal M_load_queue : T_load_queue;

    signal R_load_data : std_logic_vector(DATA_WIDTH - 1 downto 0);
    signal R_load_valid : std_logic;

    type T_lq_tail_snapshot is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal M_lq_tail_snapshot : T_lq_tail_snapshot;
    type T_lq_util_snapshot is array (0 to MAX_SPEC_BRANCHES - 1) of unsigned(LQ_TAG_WIDTH downto 0);
    signal M_lq_util_snapshot : T_lq_util_snapshot;

    signal R_lq_head : unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal R_lq_tail : unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal R_lq_util : unsigned(LQ_TAG_WIDTH downto 0);
    signal lq_head_next : unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal lq_tail_next : unsigned(LQ_TAG_WIDTH - 1 downto 0);
    signal lq_util_next : unsigned(LQ_TAG_WIDTH downto 0);

    signal lq_head_uop : T_lsu_load;
    signal lq_dispatch_enable : std_logic;

    signal lq_full : std_logic;
    signal lq_empty : std_logic;

    signal lq_enqueue : std_logic;
    signal lq_dequeue : std_logic;
    
    -- BRANCHING LOGIC
    signal uop_in_brmask_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
    signal cdb_in_brmask_index : natural range 0 to MAX_SPEC_BRANCHES - 1;
begin
    uop_in_brmask_index <= F_brmask_to_index(lsu_in_port.branch_mask);
    cdb_in_brmask_index <= F_brmask_to_index(cdb_in.branch_mask);

    sq_enqueue <= '1' when sq_full = '0' and lsu_in_port.is_store = '1' and lsu_in_port.valid = '1' else '0';
    sq_dequeue <= not sq_empty and sq_head_uop.retired and sq_head_uop.done;

    P_sq_next_calc : process(R_sq_head, R_sq_tail, R_sq_util, sq_enqueue, sq_dequeue)
    begin
        if R_sq_head = SQ_ENTRIES - 1 then
            sq_head_next <= (others => '0');
        else
            sq_head_next <= R_sq_head + 1;
        end if;

        if R_sq_tail = SQ_ENTRIES - 1 then
            sq_tail_next <= (others => '0');
        else
            sq_tail_next <= R_sq_tail + 1;
        end if;

        if sq_enqueue = '1' and sq_dequeue = '0' then
            sq_util_next <= R_sq_util + 1;
        elsif sq_enqueue = '0' and sq_dequeue = '1' then
            sq_util_next <= R_sq_util - 1;
        else
            sq_util_next <= R_sq_util;
        end if;
    end process;

    P_sq_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_sq_head <= (others => '0');
                R_sq_tail <= (others => '0');
                R_sq_util <= (others => '0');
                sq_valid <= (others => '0');
            else
                -- We encountered a speculative branch and need to take a
                -- snapshot of the current state of the SQ from the LSU
                if cdb_in.valid and cdb_in.branch_mispredicted then
                    R_sq_tail <= M_sq_tail_snapshot(cdb_in_brmask_index);

                    if sq_dequeue = '1' then
                        R_sq_util <= M_sq_util_snapshot(cdb_in_brmask_index) - 1;
                    else
                        R_sq_util <= M_sq_util_snapshot(cdb_in_brmask_index);
                    end if;
                else
                    if lsu_in_port.valid = '1' and lsu_in_port.branch_mask /= BR_MASK_ZERO then
                        M_sq_tail_snapshot(uop_in_brmask_index) <= R_sq_tail;
                        M_sq_util_snapshot(uop_in_brmask_index) <= sq_util_next;
                    end if;

                    if sq_dequeue = '1' then
                        for i in 0 to MAX_SPEC_BRANCHES - 1 loop
                            M_sq_util_snapshot(i) <= M_sq_util_snapshot(i) - 1;
                        end loop;
                    end if;

                    R_sq_util <= sq_util_next;
                end if;

                if sq_enqueue = '1' then
                    R_sq_tail <= sq_tail_next;
                    sq_valid(to_integer(R_sq_tail)) <= '1';

                    M_store_queue(to_integer(R_sq_tail)).address <= (others => '0');
                    M_store_queue(to_integer(R_sq_tail)).address_valid <= '0';
                    M_store_queue(to_integer(R_sq_tail)).data <= (others => '0');
                    M_store_queue(to_integer(R_sq_tail)).data_valid <= '0';
                    M_store_queue(to_integer(R_sq_tail)).dispatched <= '0';
                    M_store_queue(to_integer(R_sq_tail)).done <= '0';
                    M_store_queue(to_integer(R_sq_tail)).retired <= '1';
                end if;

                if sq_dequeue = '1' then
                    R_sq_head <= sq_head_next;
                    sq_valid(to_integer(R_sq_head)) <= '0';
                end if;

                if agu_in_port.rw = '1' then
                    -- Once the address is generated by the AGU put it into the SQ
                    if agu_in_port.address_valid = '1' then
                        M_store_queue(to_integer(agu_in_port.sq_tag)).address <= agu_in_port.address;
                        M_store_queue(to_integer(agu_in_port.sq_tag)).address_valid <= '1';

                        assert sq_valid(to_integer(agu_in_port.sq_tag)) = '1'
                            report "AGU targeted invalid SQ entry" severity error;
                    end if;
                    -- Once the data is generated by the AGU put it into the SQ
                    if agu_in_port.data_valid = '1' then
                        M_store_queue(to_integer(agu_in_port.sq_tag)).data <= agu_in_port.data;
                        M_store_queue(to_integer(agu_in_port.sq_tag)).data_valid <= '1';

                        assert sq_valid(to_integer(agu_in_port.sq_tag)) = '1'
                            report "AGU targeted invalid SQ entry" severity error;
                    end if;
                end if;

                if bus_ready = '1' and sq_dispatch_enable = '1' then
                    M_store_queue(to_integer(R_sq_head)).dispatched <= '1';
                end if;

                if bus_resp.valid = '1' and bus_resp.rw = '1' then
                    M_store_queue(to_integer(bus_resp.tag(SQ_TAG_WIDTH - 1 downto 0))).done <= '1';
                end if;
            end if;
        end if;
    end process;
    sq_head_uop <= M_store_queue(to_integer(R_sq_head));
    sq_dispatch_enable <= not sq_empty and sq_head_uop.data_valid and sq_head_uop.address_valid and not sq_head_uop.dispatched and sq_head_uop.retired and not lq_dispatch_enable;
    sq_full <= '1' when R_sq_util = SQ_ENTRIES else '0';
    sq_empty <= '1' when R_sq_util = 0 else '0';

    -- ======================================
    --              LOAD QUEUE
    -- ======================================
    lq_enqueue <= '1' when lq_full = '0' and lsu_in_port.is_load = '1' and lsu_in_port.valid = '1' and
        not (cdb_in.valid = '1' and cdb_in.branch_mispredicted = '1') else '0';
    lq_dequeue <= not lq_empty and lq_head_uop.done;

    P_lq_next_calc : process(R_lq_head, R_lq_tail, lq_enqueue, lq_dequeue, R_lq_util)
    begin
        if R_lq_head = LQ_ENTRIES - 1 then
            lq_head_next <= (others => '0');
        else
            lq_head_next <= R_lq_head + 1;
        end if;

        if R_lq_tail = LQ_ENTRIES - 1 then
            lq_tail_next <= (others => '0');
        else 
            lq_tail_next <= R_lq_tail + 1;
        end if;

        if lq_enqueue = '1' and lq_dequeue = '0' then
            lq_util_next <= R_lq_util + 1;
        elsif lq_enqueue = '0' and lq_dequeue = '1' then
            lq_util_next <= R_lq_util - 1;
        else
            lq_util_next <= R_lq_util;
        end if;
    end process;

    P_lq_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_lq_head <= (others => '0');
                R_lq_tail <= (others => '0');
                R_lq_util <= (others => '0');
                R_load_valid <= '0';
            else
                if cdb_in.valid and cdb_in.branch_mispredicted then
                    R_lq_tail <= M_lq_tail_snapshot(cdb_in_brmask_index);

                    if lq_dequeue = '1' then
                        R_lq_util <= M_lq_util_snapshot(cdb_in_brmask_index) - 1;
                    else
                        R_lq_util <= M_lq_util_snapshot(cdb_in_brmask_index);
                    end if;
                else
                    if lsu_in_port.valid = '1' and lsu_in_port.branch_mask /= BR_MASK_ZERO then
                        M_lq_tail_snapshot(uop_in_brmask_index) <= R_lq_tail;
                        M_lq_util_snapshot(uop_in_brmask_index) <= lq_util_next;
                    end if;

                    if lq_dequeue = '1' then
                        for i in 0 to MAX_SPEC_BRANCHES - 1 loop
                            M_lq_util_snapshot(i) <= M_lq_util_snapshot(i) - 1;
                        end loop;
                    end if;

                    R_lq_util <= lq_util_next;
                end if;

                if lq_enqueue = '1' then
                    R_lq_tail <= lq_tail_next;

                    M_load_queue(to_integer(R_lq_tail)).address <= (others => '0');
                    M_load_queue(to_integer(R_lq_tail)).address_valid <= '0';
                    M_load_queue(to_integer(R_lq_tail)).phys_dst_reg <= lsu_in_port.phys_dst_reg;
                    M_load_queue(to_integer(R_lq_tail)).store_mask <= sq_valid;
                    M_load_queue(to_integer(R_lq_tail)).dispatched <= '0';
                    M_load_queue(to_integer(R_lq_tail)).done <= '0';
                end if;

                if lq_dequeue = '1' then
                    R_lq_head <= lq_head_next;
                end if;

                if sq_dequeue = '1' then
                    for i in 0 to LQ_ENTRIES - 1 loop
                        M_load_queue(i).store_mask(to_integer(R_sq_head)) <= '0';
                    end loop;
                end if;

                if agu_in_port.rw = '0' then
                    assert agu_in_port.data_valid = '0'
                        report "Data Valid = 1 on LOAD ADDR GEN from AGU" severity error;

                    -- Once the address is generated by the AGU put it into the SQ
                    if agu_in_port.address_valid = '1' then
                        M_load_queue(to_integer(agu_in_port.lq_tag)).address <= agu_in_port.address;
                        M_load_queue(to_integer(agu_in_port.lq_tag)).address_valid <= '1';
                        
                        assert sq_valid(to_integer(agu_in_port.sq_tag)) = '1'
                        report "AGU targeted invalid LQ entry" severity error;
                    end if;
                end if;

                if bus_ready = '1' and lq_dispatch_enable = '1' then
                    M_load_queue(to_integer(R_lq_head)).dispatched <= '1';
                end if;

                if bus_resp.valid = '1' and bus_resp.rw = '0' then
                    R_load_data <= bus_resp.data;
                    R_load_valid <= '1';
                end if;

                if cdb_request = '1' and cdb_granted = '1' then
                    M_load_queue(to_integer(R_lq_head)).done <= '1';
                    R_load_valid <= '0';
                end if;
            end if;
        end if;
    end process;
    lq_head_uop <= M_load_queue(to_integer(R_lq_head));
    lq_dispatch_enable <= '1' when lq_empty = '0' and  lq_head_uop.address_valid = '1' and lq_head_uop.dispatched = '0' and lq_head_uop.store_mask = STORE_MASK_ZERO else '0';

    lq_full <= '1' when R_lq_util = LQ_ENTRIES else '0';
    lq_empty <= '1' when R_lq_util = 0 else '0'; 
    -- ======================================
    --             BUS OUTPUT
    -- ======================================
    -- Check that we don't try to dispatch bots a load and a store at the same
    -- time, sine that if for now not possible
    assert lq_dispatch_enable = '0' or sq_dispatch_enable = '0'
        report "LQ Dispatch Enable and SQ Dispatch Enable both 1 at the same time" severity error;
    
    process(lq_head_uop, lq_dispatch_enable, sq_head_uop, sq_dispatch_enable, R_lq_head, R_sq_head)
    begin
        bus_req.tag <= (others => '0');
        if lq_dispatch_enable = '1' then
            bus_req.address <= lq_head_uop.address;
            bus_req.data <= (others => '0');
            bus_req.data_size <= "00";
            bus_req.rw <= '0';
            bus_req.tag(LQ_TAG_WIDTH - 1 downto 0) <= R_lq_head;
            bus_req.valid <= '1';
        else
            bus_req.address <= sq_head_uop.address;
            bus_req.data <= sq_head_uop.data;
            bus_req.data_size <= "00";
            bus_req.rw <= '1';
            bus_req.tag(SQ_TAG_WIDTH - 1 downto 0) <= R_sq_head;
            bus_req.valid <= sq_dispatch_enable;
        end if;
    end process;
    
    cdb_out.phys_dst_reg <= lq_head_uop.phys_dst_reg;
    cdb_out.reg_write_data <= R_load_data;
    cdb_out.valid <= R_load_valid;
    cdb_request <= R_load_valid;

    lsu_out_port.sq_index <= R_sq_tail;
    lsu_out_port.lq_index <= R_lq_tail;

    stall_out <= '1' when ((sq_full = '1' and lsu_in_port.is_store = '1') or
                          (lq_full = '1' and lsu_in_port.is_load = '1')) and lsu_in_port.valid = '1' else '0';
end rtl;
