library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity cache is
    generic(
        ADDRESS_WIDTH: natural;                -- MUST BE POWER OF 2
        ASSOCIATIVITY: natural;                -- MUST BE POWER OF 2
        BYTES_PER_WORD: natural;               -- MUST BE POWER OF 2
        WORDS_PER_CACHELINE: natural;          -- MUST BE POWER OF 2
        NUM_BLOCKS: natural                -- MUST BE POWER OF 2
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        cancel_all: in std_logic;
        stall_out: out std_logic;
        bus_req: in T_bus_request;
        bus_resp: out T_bus_response;
        bus_req2: out T_bus_request;
        bus_resp2: in T_bus_response
    );
end cache;

architecture rtl of cache is
    constant C_cacheline_index_width: natural := F_min_bits(ASSOCIATIVITY);
    constant C_block_index_width: natural := F_min_bits(NUM_BLOCKS);
    -- Next two constants contain the range of bits in the address which
    -- correspond to the cacheline's index
    constant C_block_index_lsb: natural := F_min_bits(BYTES_PER_WORD) + F_min_bits(WORDS_PER_CACHELINE);
    constant C_block_index_msb: natural := C_block_index_lsb + F_min_bits(NUM_BLOCKS) - 1;
    -- Min and Max values that cacheline index signals can take
    constant C_cacheline_index_min: unsigned(C_block_index_width - 1 downto 0) := (others => '0');
    constant C_cacheline_index_max: unsigned(C_block_index_width - 1 downto 0) := (others => '1');
    -- Number of bits in the tag field
    constant C_cacheline_tag_lsb: natural := C_block_index_msb + 1;
    constant C_cacheline_tag_msb: natural := ADDRESS_WIDTH - 1;
    constant C_cacheline_tag_width: natural := ADDRESS_WIDTH - C_block_index_msb - 1;

    constant C_cacheline_word_index_lsb: natural := 2;
    constant C_cacheline_word_index_msb: natural := C_block_index_lsb - 1;
    constant C_cacheline_word_index_width: natural := F_min_bits(BYTES_PER_WORD * WORDS_PER_CACHELINE);

    type T_cacheline is record
        tag: std_logic_vector(C_cacheline_tag_width - 1 downto 0);
        data: std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);
        state: std_logic_vector(1 downto 0);
    end record;

    type T_cache_block is array (0 to ASSOCIATIVITY - 1) of T_cacheline;
    
    type T_cache_request is record
        tag: unsigned(C_cacheline_tag_width - 1 downto 0);
        block_index: unsigned(C_block_index_width - 1 downto 0);
        word_index: unsigned(C_cacheline_word_index_width - 1 downto 2);
        rw: std_logic;
        cancelled: std_logic;
        valid: std_logic;
    end record;
    
    type T_cache_response is record
        data: std_logic_vector(BYTES_PER_WORD * 8 - 1 downto 0);
        valid: std_logic;
    end record;

    type T_cache is array (0 to NUM_BLOCKS - 1) of T_cache_block;
    signal M_cache: T_cache;

    constant CL_STATE_INVALID: std_logic_vector(1 downto 0) := "00";
    constant CL_STATE_EXCLUSIVE: std_logic_vector(1 downto 0) := "01";
    constant CL_STATE_SHARED: std_logic_vector(1 downto 0) := "10";
    constant CL_STATE_MODIFIED: std_logic_vector(1 downto 0) := "11";
    type T_cache_control_sm is (INITIALIZE, NORMAL, FETCH, WRITEBACK, RETRY);
    signal R_cache_control_sm: T_cache_control_sm;

    signal R_init_cacheline_counter: unsigned(C_block_index_width - 1 downto 0);
    signal cacheline_read: T_cacheline;
    signal R_cache_request: T_cache_request;
    signal R_cache_response: T_cache_response;

    signal cache_hit: std_logic;

    signal R_random_selector: unsigned(C_cacheline_index_width - 1 downto 0);

    signal cache_read_word: std_logic_vector(BYTES_PER_WORD * 8 - 1 downto 0);
    signal cache_block_pointer: unsigned(C_block_index_width - 1 downto 0);
    signal cache_block_read: T_cache_block;
    signal cache_block_full: std_logic;
    signal cache_block_free_index: unsigned(C_cacheline_index_width - 1 downto 0);
    signal cache_block_writeback_index: unsigned(C_cacheline_index_width - 1 downto 0);
    signal cache_block_read_index: unsigned(C_cacheline_index_width - 1 downto 0);

    signal R_cache_fetch_cacheline_data: std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);
    signal R_cache_fetch_address: unsigned(ADDRESS_WIDTH - 1 downto 0);
    signal R_cache_fetch_burst_len: unsigned(7 downto 0);
    signal R_cache_fetch_burst_counter: unsigned(7 downto 0);
begin
    bus_req2.address <= std_logic_vector(R_cache_fetch_address);
    bus_req2.valid <= '1' when R_cache_control_sm = FETCH else '0';
    bus_req2.data_size <= "10";
    bus_req2.is_unsigned <= '1';
    bus_req2.rw <= '0';
    bus_req2.burst_len <= R_cache_fetch_burst_len;

    process(cache_block_read)
    begin
        cache_block_full <= '1';
        cache_block_free_index <= (others => '0');
        for i in 0 to ASSOCIATIVITY - 1 loop
            if cache_block_read(i).state = CL_STATE_INVALID then
                cache_block_free_index <= to_unsigned(i, C_cacheline_index_width);
                cache_block_full <= '0';
            end if;
        end loop;

        if ASSOCIATIVITY = 1 then
            cache_block_writeback_index <= (others => '0');
        else
            cache_block_writeback_index <= R_random_selector when cache_block_full else cache_block_free_index;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_cache_control_sm <= INITIALIZE;
                R_init_cacheline_counter <= (others => '0');
                R_random_selector <= (others => '0');
            else
                R_random_selector <= R_random_selector + 1;

                case R_cache_control_sm is
                when NORMAL =>
                    if R_cache_request.valid = '1' and
                         cache_hit = '0' then
                        R_cache_control_sm <= FETCH;
                        -- Generate fetch address that is aligned to cacheline length
                        R_cache_fetch_address <= (others => '0');
                        R_cache_fetch_address(C_cacheline_tag_msb downto C_cacheline_tag_lsb) <= R_cache_request.tag;
                        R_cache_fetch_address(C_block_index_msb downto C_block_index_lsb) <= unsigned(R_cache_request.block_index);
                        -- Burst len equal to number of words in a cacheline
                        R_cache_fetch_burst_len <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                        R_cache_fetch_burst_counter <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);

                        if cancel_all = '1' then
                            R_cache_request.cancelled <= '1';
                        end if;
                    else
                        cache_block_read <= M_cache(to_integer(cache_block_pointer));
                        R_cache_request.tag <= unsigned(bus_req.address(C_cacheline_tag_msb downto C_cacheline_tag_lsb));
                        R_cache_request.block_index <= unsigned(bus_req.address(C_block_index_msb downto C_block_index_lsb));
                        R_cache_request.word_index <= unsigned(bus_req.address(C_cacheline_word_index_msb downto C_cacheline_word_index_lsb));
                        R_cache_request.rw <= bus_req.rw;
                        R_cache_request.cancelled <= '0';
                        R_cache_request.valid <= bus_req.valid;
                    end if;
                when INITIALIZE =>      -- Initializes all cacheline states to INVALID (empty)
                    if R_init_cacheline_counter = C_cacheline_index_max then
                        R_cache_control_sm <= NORMAL;
                    end if;

                    for i in 0 to ASSOCIATIVITY - 1 loop
                        M_cache(to_integer(R_init_cacheline_counter))(i).state <= CL_STATE_INVALID;
                    end loop;
                    R_init_cacheline_counter <= R_init_cacheline_counter + 1;
                when FETCH =>
                    if bus_resp2.valid = '1' then
                        if R_cache_fetch_burst_counter = 0 then
                            R_cache_control_sm <= WRITEBACK;
                        else
                            R_cache_fetch_burst_counter <= R_cache_fetch_burst_counter - 1;
                        end if;
                        
                        for i in 0 to WORDS_PER_CACHELINE - 1 loop
                            if (WORDS_PER_CACHELINE - 1 - to_integer(R_cache_fetch_burst_counter)) = i then
                                R_cache_fetch_cacheline_data(BYTES_PER_WORD * 8 * (i + 1) - 1 downto BYTES_PER_WORD * 8 * i) <=
                                  bus_resp2.data;
                            end if;
                        end loop;
                    end if;

                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;
                when WRITEBACK =>
                    R_cache_control_sm <= RETRY;
                    M_cache(to_integer(R_cache_request.block_index))(to_integer(cache_block_writeback_index)).data
                      <= R_cache_fetch_cacheline_data;
                    M_cache(to_integer(R_cache_request.block_index))(to_integer(cache_block_writeback_index)).tag
                      <= std_logic_vector(R_cache_fetch_address(C_cacheline_tag_msb downto C_cacheline_tag_lsb));
                    M_cache(to_integer(R_cache_request.block_index))(to_integer(cache_block_writeback_index)).state
                      <= CL_STATE_EXCLUSIVE;

                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;
                when RETRY =>
                    R_cache_control_sm <= NORMAL;
                    cache_block_read <= M_cache(to_integer(cache_block_pointer));

                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;
                when others =>
                end case;
            end if;
        end if;
    end process;

    process(R_cache_request.valid, R_cache_request.tag, cache_block_read, cache_block_read_index)
    begin
        cache_hit <= '0';
        cache_block_read_index <= (others => '0');
        if R_cache_request.valid = '1' then
            for i in 0 to ASSOCIATIVITY - 1 loop
                if R_cache_request.tag = unsigned(cache_block_read(i).tag) and cache_block_read(i).state /= CL_STATE_INVALID then
                    cache_block_read_index <= to_unsigned(i, C_cacheline_index_width);
                    cache_hit <= '1';
                end if;
            end loop;
        end if;
        cacheline_read <= cache_block_read(to_integer(cache_block_read_index));
    end process;

    process(cacheline_read, R_cache_request.word_index)
    begin
        cache_read_word <= (others => '0');
        for i in 0 to WORDS_PER_CACHELINE - 1 loop
            if to_integer(unsigned(R_cache_request.word_index)) = i then
                cache_read_word <= cacheline_read.data(8 * BYTES_PER_WORD * (i + 1) - 1 downto 8 * BYTES_PER_WORD * i);
            end if;
        end loop;
    end process;
    
    process(R_cache_control_sm, R_init_cacheline_counter, R_cache_request, bus_req.address, cache_hit)
    begin
        stall_out <= '0';
        cache_block_pointer <= (others => '0');
        case R_cache_control_sm is
        when NORMAL =>
            if R_cache_request.valid = '1' and
                 cache_hit = '0' then
                stall_out <= '1';
            end if;

            cache_block_pointer <= unsigned(bus_req.address(C_block_index_msb downto C_block_index_lsb));
            R_cache_response.valid <= '0';
        when INITIALIZE =>
            cache_block_pointer <= R_init_cacheline_counter;
            stall_out <= '1';
        when FETCH =>
            stall_out <= '1';
        when WRITEBACK =>
            stall_out <= '1';
        when RETRY =>
            cache_block_pointer <= R_cache_request.block_index;
            stall_out <= '1';
        when others =>
        end case;
    end process;

    bus_resp.address <= std_logic_vector(R_cache_request.tag & R_cache_request.block_index & R_cache_request.word_index) & "00";
    bus_resp.data <= cache_read_word;
    bus_resp.valid <= R_cache_request.valid and not R_cache_request.cancelled and cache_hit;
end rtl;
