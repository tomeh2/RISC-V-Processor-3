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
        NUM_BLOCKS: natural;                   -- MUST BE POWER OF 2
        IS_BLOCKING: boolean
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        cancel_all: in std_logic;
        stall_out: out std_logic;
        cpu_bus_req: in T_bus_request;
        cpu_bus_resp: out T_bus_response;
        ext_bus_req: out T_bus_request;
        ext_bus_resp: in T_bus_response
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

    constant C_cacheline_data_width: natural := 8 * BYTES_PER_WORD * WORDS_PER_CACHELINE;
    constant C_cacheline_width: natural := C_cacheline_tag_width + C_cacheline_data_width + 2;
    constant C_temp_state_lsb: natural := 0;
    constant C_temp_state_msb: natural := 1;
    constant C_temp_data_lsb: natural := 2;
    constant C_temp_data_msb: natural := C_cacheline_data_width + C_temp_data_lsb - 1;
    constant C_temp_tag_lsb: natural := C_temp_data_msb + 1;
    constant C_temp_tag_msb: natural := C_temp_tag_lsb + C_cacheline_tag_width - 1;

    constant C_cacheline_word_index_lsb: natural := 2;
    constant C_cacheline_word_index_msb: natural := C_block_index_lsb - 1;
    constant C_cacheline_word_index_width: natural := F_min_bits(BYTES_PER_WORD * WORDS_PER_CACHELINE);

    type T_cacheline is record
        tag: std_logic_vector(C_cacheline_tag_width - 1 downto 0);
        data: std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);
        state: std_logic_vector(1 downto 0);
    end record;
    type T_cache_block is array (0 to ASSOCIATIVITY - 1) of T_cacheline;

    subtype T_cacheline_data is std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);
    type T_cache_data is array (0 to NUM_BLOCKS - 1) of T_cacheline_data;
    type T_cache_data_array is array (0 to ASSOCIATIVITY - 1) of T_cache_data;
    signal M_cache_data: T_cache_data_array;
    type T_cache_tags is array (0 to NUM_BLOCKS - 1) of std_logic_vector(C_cacheline_tag_width - 1 downto 0);
    type T_cache_tags_array is array (0 to ASSOCIATIVITY - 1) of T_cache_tags;
    signal M_cache_tags: T_cache_tags_array;
    type T_cache_states is array (0 to NUM_BLOCKS - 1) of std_logic_vector(1 downto 0);
    type T_cache_states_array is array (0 to ASSOCIATIVITY - 1) of T_cache_states;
    signal M_cache_states: T_cache_states_array;

    type T_cacheline_mem_read_data is array (0 to ASSOCIATIVITY - 1) of std_logic_vector(C_cacheline_width - 1 downto 0);
    signal cacheline_mem_read_data: T_cacheline_mem_read_data;
    signal cacheline_mem_write_data: std_logic_vector(C_cacheline_width - 1 downto 0);
    signal cacheline_mem_read_addr: std_logic_vector(C_block_index_width - 1 downto 0);
    signal cacheline_mem_write_addr: std_logic_vector(C_block_index_width - 1 downto 0);
    signal cacheline_mem_write_enable: std_logic_vector(ASSOCIATIVITY - 1 downto 0);

    type T_cache_request is record
        address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0); 
        rw: std_logic;
        cancelled: std_logic;
        valid: std_logic;
    end record;
    
    type T_cache_response is record
        data: std_logic_vector(BYTES_PER_WORD * 8 - 1 downto 0);
        valid: std_logic;
    end record;

    constant CL_STATE_INVALID: std_logic_vector(1 downto 0) := "00";
    constant CL_STATE_EXCLUSIVE: std_logic_vector(1 downto 0) := "01";
    constant CL_STATE_SHARED: std_logic_vector(1 downto 0) := "10";
    constant CL_STATE_MODIFIED: std_logic_vector(1 downto 0) := "11";
    type T_cache_control_sm is (INITIALIZE, NORMAL, STALL, STALL_FETCH);
    signal R_cache_control_sm: T_cache_control_sm;

    signal R_init_cacheline_counter: unsigned(C_block_index_width - 1 downto 0);
    signal cacheline_read: std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);
    signal R_cache_request: T_cache_request;
    signal R_cache_response: T_cache_response;

    signal cache_hit: std_logic;

    signal R_random_selector: unsigned(C_cacheline_index_width - 1 downto 0);

    signal cache_read_word: std_logic_vector(BYTES_PER_WORD * 8 - 1 downto 0);
    signal cache_block_read: T_cache_block;
    signal cache_block_full: std_logic;
    signal cache_block_free_index: unsigned(C_cacheline_index_width - 1 downto 0);
    signal cache_block_writeback_index: unsigned(C_cacheline_index_width - 1 downto 0);
    signal cache_block_read_index: unsigned(C_cacheline_index_width - 1 downto 0);

    type T_fetcher_req is record
        address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
        valid: std_logic;
    end record;
    signal fetcher_req: T_fetcher_req;
    type T_fetcher_sm is (IDLE, BUSY, WRITEBACK);
    signal R_fetcher_sm: T_fetcher_sm;
    signal fetcher_ready: std_logic;
    signal fetcher_cacheline_valid: std_logic;
    signal R_fetcher_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal R_fetcher_burst_counter: unsigned(7 downto 0);
    signal R_fetcher_burst_len: unsigned(7 downto 0);
    signal R_fetcher_cacheline_data: std_logic_vector(BYTES_PER_WORD * WORDS_PER_CACHELINE * 8 - 1 downto 0);

    function F_extract_tag(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_cacheline_tag_msb downto C_cacheline_tag_lsb);
    end function;

    function F_extract_block(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_block_index_msb downto C_block_index_lsb);
    end function;

    function F_extract_word(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_cacheline_word_index_msb downto C_cacheline_word_index_lsb);
    end function;

    function F_extract_block_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_extract_block(address)));
    end function;

    function F_extract_word_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_extract_word(address)));
    end function;

    procedure F_cacheline_pack(signal tag: in std_logic_vector(C_cacheline_tag_width - 1 downto 0);
        signal data: in std_logic_vector(C_cacheline_data_width - 1 downto 0);
        constant state: in std_logic_vector(1 downto 0);
        signal packed_cacheline: out std_logic_vector(C_cacheline_width - 1 downto 0)) is
    begin
        packed_cacheline <= tag & data & state;
    end procedure;

    procedure F_cacheline_unpack(signal cacheline_packed: in std_logic_vector(C_cacheline_width - 1 downto 0);
        signal tag: out std_logic_vector(C_cacheline_tag_width - 1 downto 0);
        signal data: out std_logic_vector(C_cacheline_data_width - 1 downto 0);
        signal state: out std_logic_vector(1 downto 0)) is
    begin
        tag <= cacheline_packed(C_temp_tag_msb downto C_temp_tag_lsb);
        data <= cacheline_packed(C_temp_data_msb downto C_temp_data_lsb);
        state <= cacheline_packed(C_temp_state_msb downto C_temp_state_lsb);
    end procedure;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_fetcher_sm <= IDLE;
            else
                case R_fetcher_sm is
                when IDLE =>
                    if fetcher_req.valid = '1' then
                        R_fetcher_sm <= BUSY;
                        R_fetcher_address <= fetcher_req.address;
                        R_fetcher_burst_counter <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                        R_fetcher_burst_len <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                    end if;
                when BUSY =>
                    if ext_bus_resp.valid = '1' then
                        R_fetcher_burst_counter <= R_fetcher_burst_counter - 1;
    
                        for i in 0 to WORDS_PER_CACHELINE - 1 loop
                            if (WORDS_PER_CACHELINE - 1 - to_integer(R_fetcher_burst_counter)) = i then
                                R_fetcher_cacheline_data(BYTES_PER_WORD * 8 * (i + 1) - 1 downto BYTES_PER_WORD * 8 * i) <=
                                  ext_bus_resp.data;
                            end if;
                        end loop;
    
                        if R_fetcher_burst_counter = 0 then
                            R_fetcher_sm <= WRITEBACK;
                        end if;
                    end if;
                when WRITEBACK =>
                    R_fetcher_sm <= IDLE;
                end case;
            end if;
        end if;
    end process;

    process(R_fetcher_sm)
    begin
        fetcher_cacheline_valid <= '0';
        fetcher_ready <= '1';
        case R_fetcher_sm is
        when IDLE =>
            
        when BUSY =>
            fetcher_ready <= '0';
        when WRITEBACK =>
            fetcher_cacheline_valid <= '1';
            fetcher_ready <= '0';
        end case;
    end process;

    ext_bus_req.address <= std_logic_vector(R_fetcher_address);
    ext_bus_req.valid <= '1' when R_fetcher_sm = BUSY else '0';
    ext_bus_req.data_size <= "10";
    ext_bus_req.is_unsigned <= '1';
    ext_bus_req.rw <= '0';
    ext_bus_req.burst_len <= R_fetcher_burst_len;

    -- MEMORY DEFINITION
    F_cacheline_pack(R_fetcher_address(C_cacheline_tag_msb downto C_cacheline_tag_lsb),
        R_fetcher_cacheline_data,
        CL_STATE_EXCLUSIVE,
        cacheline_mem_write_data);
    G_gen_memory: for i in 0 to ASSOCIATIVITY - 1 generate
        cacheline_mem_write_enable(i) <= '1' when cache_block_writeback_index = i and fetcher_cacheline_valid = '1' else '0';
        I_cache_memblk: entity work.bram
        generic map(
            WORD_LENGTH => C_cacheline_width,
            NUM_WORDS => NUM_BLOCKS
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_addr,
            write_enable => cacheline_mem_write_enable(i),
            data_write => cacheline_mem_write_data,
            addr_read => cacheline_mem_read_addr,
            data_read => cacheline_mem_read_data(i)
        );  
    end generate;

    process(M_cache_states)
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
                if ASSOCIATIVITY = 1 then
                    R_random_selector <= (others => '0');
                else
                    R_random_selector <= R_random_selector + 1;
                end if;

                case R_cache_control_sm is
                when NORMAL =>
                    if R_cache_request.valid = '1' and
                         cache_hit = '0' then
                        if fetcher_ready = '1' then
                            R_cache_control_sm <= STALL_FETCH;
                        else
                            R_cache_control_sm <= STALL;
                        end if;

                        if cancel_all = '1' then
                            R_cache_request.cancelled <= '1';
                        end if;
                    else
                        R_cache_request.address <= cpu_bus_req.address;
                        R_cache_request.rw <= cpu_bus_req.rw;
                        R_cache_request.cancelled <= '0';
                        R_cache_request.valid <= cpu_bus_req.valid;
                    end if;
                when INITIALIZE =>      -- Initializes all cacheline states to INVALID (empty)
                    if R_init_cacheline_counter = C_cacheline_index_max then
                        R_cache_control_sm <= NORMAL;
                    end if;

                    for i in 0 to ASSOCIATIVITY - 1 loop
                        M_cache_states(i)(to_integer(R_init_cacheline_counter)) <= CL_STATE_INVALID;
                    end loop;
                    R_init_cacheline_counter <= R_init_cacheline_counter + 1;
                when STALL =>
                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;

                    if fetcher_ready = '1' then
                        R_cache_control_sm <= NORMAL;
                    end if;
                when STALL_FETCH =>
                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;

                    if cache_hit = '1' then
                        R_cache_control_sm <= NORMAL;
                        R_cache_request.address <= cpu_bus_req.address;
                        R_cache_request.rw <= cpu_bus_req.rw;
                        R_cache_request.cancelled <= '0';
                        R_cache_request.valid <= cpu_bus_req.valid;
                    else
                    end if;
                when others =>
                end case;
            end if;
        end if;
    end process;

    process(cacheline_mem_read_data)
    begin
        for i in 0 to ASSOCIATIVITY - 1 loop
            F_cacheline_unpack(cacheline_mem_read_data(i),
                cache_block_read(i).tag,
                cache_block_read(i).data,
                cache_block_read(i).state);
        end loop;
    end process;

    process(R_cache_request.valid, R_cache_request.address, cache_block_read, cache_block_read_index)
    begin
        cache_hit <= '0';
        cache_block_read_index <= (others => '0');
        if R_cache_request.valid = '1' then
            for i in 0 to ASSOCIATIVITY - 1 loop
                if F_extract_tag(R_cache_request.address) = cache_block_read(i).tag and cache_block_read(i).state /= CL_STATE_INVALID then
                    cache_block_read_index <= to_unsigned(i, C_cacheline_index_width);
                    cache_hit <= '1';
                end if;
            end loop;
        end if;
        cacheline_read <= cache_block_read(to_integer(cache_block_read_index)).data;
    end process;

    process(cacheline_read, R_cache_request.address)
    begin
        cache_read_word <= (others => '0');
        for i in 0 to WORDS_PER_CACHELINE - 1 loop
            if F_extract_word_index(R_cache_request.address) = i then
                cache_read_word <= cacheline_read(8 * BYTES_PER_WORD * (i + 1) - 1 downto 8 * BYTES_PER_WORD * i);
            end if;
        end loop;
    end process;
    
    process(R_cache_control_sm, R_init_cacheline_counter, R_cache_request, cpu_bus_req.address, cache_hit, R_fetcher_address)
    begin
        stall_out <= '0';
        fetcher_req.address <= (others => '0');
        fetcher_req.address(C_cacheline_tag_msb downto C_block_index_lsb) <= R_cache_request.address(C_cacheline_tag_msb downto C_block_index_lsb);
        fetcher_req.valid <= '0';
        cacheline_mem_read_addr <= F_extract_block(cpu_bus_req.address);
        cacheline_mem_write_addr <= F_extract_block(R_fetcher_address);
        case R_cache_control_sm is
        when NORMAL =>
            if R_cache_request.valid = '1' and
                 cache_hit = '0' then
                cacheline_mem_read_addr <= F_extract_block(R_cache_request.address);
                fetcher_req.valid <= '1';
                stall_out <= '1';
            end if;
            R_cache_response.valid <= '0';
        when INITIALIZE =>
            stall_out <= '1';
        when STALL =>
            stall_out <= '1';
        when STALL_FETCH =>
            if cache_hit = '1' then
                cacheline_mem_read_addr <= F_extract_block(cpu_bus_req.address);
            else
                cacheline_mem_read_addr <= F_extract_block(R_cache_request.address);
            end if;
            stall_out <= '0' when cache_hit = '1' else '1';
        when others =>
        end case;
    end process;

    cpu_bus_resp.address <= R_cache_request.address;
    cpu_bus_resp.data <= cache_read_word;
    cpu_bus_resp.valid <= R_cache_request.valid and not R_cache_request.cancelled and cache_hit;
end rtl;