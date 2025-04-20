library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity cache is
    generic(
        ENABLE_WRITE: boolean;
        ENABLE_UNCACHED_ADDR_RANGE: boolean;
        UNCACHED_ADDR_RANGE: std_logic_vector(3 downto 0);
        ADDRESS_WIDTH: natural;                -- MUST BE POWER OF 2
        ASSOCIATIVITY: natural;                -- MUST BE POWER OF 2
        BYTES_PER_WORD: natural;               -- MUST BE POWER OF 2
        WORDS_PER_CACHELINE: natural;          -- MUST BE POWER OF 2
        SIZE_BYTES: natural                    -- MUST BE POWER OF 2
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        -- Cancel all pending requests in the pipeline
        --stall_out: out std_logic;
        cpu_bus_req: in T_bus_request;
        cpu_bus_resp: out T_bus_response;
        ext_bus_req: out T_wishbone_req;
        ext_bus_resp: in T_wishbone_resp
    );
end cache;

architecture rtl of cache is
    -- CACHE PARAMETERS
    constant C_cachelines_per_block: natural := ASSOCIATIVITY;
    constant C_cache_block_size: natural := 8 * BYTES_PER_WORD * WORDS_PER_CACHELINE * C_cachelines_per_block;
    constant C_cache_num_blocks: natural := SIZE_BYTES / C_cache_block_size;

    -- CACHE FIELD SIZES
    constant C_cacheline_index_size: natural := F_min_bits(C_cachelines_per_block);
    constant C_cache_block_index_size: natural := F_min_bits(C_cache_num_blocks);
    constant C_cache_word_index_size: natural := F_min_bits(WORDS_PER_CACHELINE);
    constant C_cacheline_word_size: natural := 8 * BYTES_PER_WORD;
    constant C_cacheline_data_size: natural := 8 * BYTES_PER_WORD * WORDS_PER_CACHELINE;
    constant C_cacheline_state_size: natural := 2;
    constant C_cacheline_tag_size: natural := ADDRESS_WIDTH - C_cacheline_state_size - C_cache_block_index_size - C_cache_word_index_size;
    constant C_cacheline_size: natural := C_cacheline_state_size + C_cacheline_tag_size + C_cacheline_data_size;
    constant C_cacheline_size_bytes: natural := BYTES_PER_WORD * WORDS_PER_CACHELINE;

    -- MSB AND LSB CALCULATIONS FOR FIELDS IN A FULL CACHELINE
    constant C_cacheline_data_lsb: natural := 0;
    constant C_cacheline_data_msb: natural := C_cacheline_data_lsb + C_cacheline_data_size - 1;
    constant C_cacheline_tag_lsb: natural := C_cacheline_data_msb + 1;
    constant C_cacheline_tag_msb: natural := C_cacheline_tag_lsb + C_cacheline_tag_size - 1;
    constant C_cacheline_state_lsb: natural := C_cacheline_tag_msb + 1;
    constant C_cacheline_state_msb: natural := C_cacheline_state_lsb + C_cacheline_state_size - 1;

    -- MSB AND LSB CALCULATIONS FOR FIELDS IN AN ADDRESS
    constant C_address_word_index_lsb: natural := 2;
    constant C_address_word_index_msb: natural := C_address_word_index_lsb + C_cache_word_index_size - 1;
    constant C_address_block_index_lsb: natural := C_address_word_index_msb + 1;
    constant C_address_block_index_msb: natural := C_address_block_index_lsb + C_cache_block_index_size - 1;
    constant C_address_tag_lsb: natural := C_address_block_index_msb + 1;
    constant C_address_tag_msb: natural := C_address_tag_lsb + C_cacheline_tag_size - 1;

    -- DATA TYPE FOR HOLDING UNPACKED CACHELINE FIELDS
    type T_cacheline is record
        tag: std_logic_vector(C_cacheline_tag_size - 1 downto 0);
        data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
        state: std_logic_vector(1 downto 0);
    end record;
    type T_cache_block is array (0 to C_cachelines_per_block - 1) of T_cacheline;

    -- CACHELINE RAM SIGNALS
    type T_cacheline_mem_read_data is array (0 to C_cachelines_per_block - 1) of std_logic_vector(C_cacheline_size - 1 downto 0);
    signal cacheline_mem_read_data: T_cacheline_mem_read_data;
    signal cacheline_mem_read_addr: std_logic_vector(C_cache_block_index_size - 1 downto 0);
    signal cacheline_mem_write_data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal cacheline_mem_write_tag: std_logic_vector(C_cacheline_tag_size - 1 downto 0);
    signal cacheline_mem_write_state: std_logic_vector(C_cacheline_state_size - 1 downto 0);
    signal cacheline_mem_write_block_addr: std_logic_vector(C_cache_block_index_size - 1 downto 0);
    signal cacheline_mem_write_slot_index : unsigned(C_cacheline_index_size - 1 downto 0);
    signal cacheline_mem_write_data_enable: std_logic_vector(C_cachelines_per_block - 1 downto 0);
    signal cacheline_mem_write_tag_enable: std_logic_vector(C_cachelines_per_block - 1 downto 0);
    signal cacheline_mem_write_state_enable: std_logic_vector(C_cachelines_per_block - 1 downto 0);
    signal cacheline_mem_write_data_valid: std_logic;
    signal cacheline_mem_write_tag_valid: std_logic;
    signal cacheline_mem_write_state_valid: std_logic;
    signal cacheline_mem_byte_enable: std_logic_vector(C_cacheline_size_bytes - 1 downto 0);

    type T_cache_request is record
        address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
        data: std_logic_vector(BYTES_PER_WORD * 8 - 1 downto 0);
        data_size: std_logic_vector(1 downto 0);
        cacheable: std_logic;
        rw: std_logic;
        cancelled: std_logic;
        valid: std_logic;
    end record;
    
    type T_cache_response is record
        data: std_logic_vector(C_cacheline_word_size - 1 downto 0);
        valid: std_logic;
    end record;

    constant CL_STATE_INVALID: std_logic_vector(1 downto 0) := "00";
    constant CL_STATE_EXCLUSIVE: std_logic_vector(1 downto 0) := "01";
    constant CL_STATE_SHARED: std_logic_vector(1 downto 0) := "10";
    constant CL_STATE_MODIFIED: std_logic_vector(1 downto 0) := "11";
    --type T_cache_control_sm is (INITIALIZE, NORMAL, STALL_CACHE_IO_NOT_READY, STALL_IO_FETCH, STALL_IO_EVICT, CYCLE_DELAY);
    type T_cache_control_sm is (INITIALIZE, NORMAL, STALL_IO_FETCH, STALL_IO_EVICT, CYCLE_DELAY);
    signal R_cache_control_sm: T_cache_control_sm;

    signal R_init_cacheline_counter: unsigned(C_cache_block_index_size - 1 downto 0);
    signal R_cache_request: T_cache_request;
    signal R_cache_response: T_cache_response;

    signal cache_hit: std_logic;
    signal cacheline_read: T_cacheline;
    signal cacheline_evict: T_cacheline;

    signal stall: std_logic;

    signal R_random_selector: unsigned(C_cacheline_index_size - 1 downto 0);
    signal R_uncacheable_read_data: std_logic_vector(C_cacheline_word_size - 1 downto 0);
    signal R_uncacheable_read_data_valid: std_logic;

    signal cacheline_modify_byte_enable: std_logic_vector(C_cacheline_size_bytes - 1 downto 0);
    signal cacheline_modify_data_write: std_logic_vector(C_cacheline_data_size - 1 downto 0);

    signal cache_read_word: std_logic_vector(C_cacheline_word_size - 1 downto 0);

    -- CACHELINE ALLOCATOR SIGNALS
    signal clalloc_block_has_available_cacheline: std_logic;
    signal clalloc_block_has_clean_cacheline: std_logic;
    signal clalloc_free_cacheline_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal clalloc_clean_cacheline_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal clalloc_evict_cacheline_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal clalloc_allocated_cacheline_index: unsigned(C_cacheline_index_size - 1 downto 0);

    -- CACHE BLOCK SIGNALS
    signal cache_block_read: T_cache_block;
    --signal cache_block_full: std_logic;
    signal cache_block_needs_eviction: std_logic;
    signal cache_block_free_index: unsigned(C_cacheline_index_size - 1 downto 0);
    -- Index in a block where the newly fetched cacheline will be stored
    signal cache_block_allocation_index: unsigned(C_cacheline_index_size - 1 downto 0);
    -- Index of the cache block in which a hit was detected
    signal cache_block_hit_slot_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal cache_block_evict_slot_index: unsigned(C_cacheline_index_size - 1 downto 0);

    -- CACHE IO SIGNALS
    signal cacheio_req_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal cacheio_req_data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal cacheio_req_data_size: std_logic_vector(1 downto 0);
    signal cacheio_req_noncacheable: std_logic;
    signal cacheio_req_rw: std_logic;
    signal cacheio_req_ready: std_logic;
    signal cacheio_req_valid: std_logic;
    signal cacheio_resp_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal cacheio_resp_data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal cacheio_resp_valid: std_logic;
    signal cacheio_resp_ready: std_logic;

    -- FUNCTIONS
    function F_get_tag_vector(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_address_tag_msb downto C_address_tag_lsb);
    end function;

    function F_get_block_vector(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_address_block_index_msb downto C_address_block_index_lsb);
    end function;

    function F_get_word_vector(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_address_word_index_msb downto C_address_word_index_lsb);
    end function;
    
    function F_get_halfword_vector(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_address_word_index_msb downto 1);
    end function;

    function F_get_byte_vector(address: std_logic_vector) return std_logic_vector is
    begin
        return address(C_address_word_index_msb downto 0);
    end function;

    function F_get_block_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_block_vector(address)));
    end function;

    function F_get_word_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_word_vector(address)));
    end function;
    
    function F_get_halfword_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_halfword_vector(address)));
    end function;

    function F_get_byte_index(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_byte_vector(address)));
    end function;
begin
    I_cacheio: entity work.cache_io
    generic map(ADDRESS_WIDTH => ADDRESS_WIDTH,
        CACHELINE_DATA_WIDTH => C_cacheline_data_size,
        BYTES_PER_WORD => BYTES_PER_WORD,
        WORDS_PER_CACHELINE => WORDS_PER_CACHELINE)
    port map(clk => clk,
             reset => reset,
             cacheio_req_address => cacheio_req_address,
             cacheio_req_data => cacheio_req_data,
             cacheio_req_data_size => cacheio_req_data_size,
             cacheio_req_rw => cacheio_req_rw,
             cacheio_req_noncacheable => cacheio_req_noncacheable,
             cacheio_req_ready => cacheio_req_ready,
             cacheio_req_valid => cacheio_req_valid,
             cacheio_resp_address => cacheio_resp_address,
             cacheio_resp_data => cacheio_resp_data,
             cacheio_resp_ready => cacheio_resp_ready,
             cacheio_resp_valid => cacheio_resp_valid,
             external_bus_req => ext_bus_req,
             external_bus_resp => ext_bus_resp);

    -- MEMORY DEFINITION
    G_gen_memory: for i in 0 to ASSOCIATIVITY - 1 generate
    begin
        cacheline_mem_write_data_enable(i) <= '1' when (cacheline_mem_write_slot_index = i and cacheline_mem_write_data_valid = '1') else '0';
        cacheline_mem_write_tag_enable(i) <= '1' when (cacheline_mem_write_slot_index = i and cacheline_mem_write_tag_valid = '1') else '0';
        cacheline_mem_write_state_enable(i) <= '1' when (cacheline_mem_write_slot_index = i and cacheline_mem_write_state_valid = '1') else '0';
        I_cache_ram_data: entity work.bram
        generic map(
            USE_BYTE_ENABLE => true,
            WORD_LENGTH => C_cacheline_data_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_block_addr,
            write_enable => cacheline_mem_write_data_enable(i),
            byte_enable => cacheline_mem_byte_enable,
            data_write => cacheline_mem_write_data,
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).data
        );  
        
        I_cache_ram_tags: entity work.bram
        generic map(
            USE_BYTE_ENABLE => false,
            WORD_LENGTH => C_cacheline_tag_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_block_addr,
            write_enable => cacheline_mem_write_tag_enable(i),
            data_write => cacheline_mem_write_tag,
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).tag
        );

        I_cache_ram_states: entity work.bram
        generic map(
            USE_BYTE_ENABLE => false,
            WORD_LENGTH => C_cacheline_state_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_block_addr,
            write_enable => cacheline_mem_write_state_enable(i),
            data_write => cacheline_mem_write_state,
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).state
        );
    end generate;

    -- CACHELINE ALLOCATOR & EVICTOR
    process(cache_block_read, R_random_selector, clalloc_block_has_available_cacheline, 
        clalloc_block_has_clean_cacheline, clalloc_free_cacheline_index, clalloc_clean_cacheline_index,
        clalloc_evict_cacheline_index, clalloc_allocated_cacheline_index)
    begin
        clalloc_block_has_available_cacheline <= '0';

        -- Search the cache block for any empty cachelines
        for i in 0 to ASSOCIATIVITY - 1 loop
            if cache_block_read(i).state = CL_STATE_INVALID then
                clalloc_free_cacheline_index <= to_unsigned(i, C_cacheline_index_size);
                clalloc_block_has_available_cacheline <= '1';
            end if;
        end loop;

        -- Search the cache block for any cachelines that do not need eviction
        -- before allocation
        clalloc_block_has_clean_cacheline <= '0';
        for i in 0 to ASSOCIATIVITY - 1 loop
            if cache_block_read(i).state = CL_STATE_EXCLUSIVE then
                clalloc_clean_cacheline_index <= to_unsigned(i, C_cacheline_index_size);
                clalloc_block_has_clean_cacheline <= '1';
            end if;
        end loop;

        -- Pick a cacheline to evict (at random)
        clalloc_evict_cacheline_index <= R_random_selector;
        cache_block_needs_eviction <= not clalloc_block_has_available_cacheline and not clalloc_block_has_clean_cacheline;

        -- First check for any free cachelines
        if clalloc_block_has_available_cacheline = '1' then
            clalloc_allocated_cacheline_index <= clalloc_free_cacheline_index;
        -- Then check for any clean cachelines to evict
        elsif clalloc_block_has_clean_cacheline = '1' then
            clalloc_allocated_cacheline_index <= clalloc_clean_cacheline_index;
        -- No free or clean cachelines... need eviction... oh well
        else
            clalloc_allocated_cacheline_index <= clalloc_evict_cacheline_index;
        end if;
        cacheline_evict <= cache_block_read(to_integer(clalloc_allocated_cacheline_index));
    end process;

    -- CACHE REQUEST CONSTRUCTOR
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_cache_request.valid <= '0';
            else
                -- Accept new request
                if stall /= '1' and cpu_bus_req.valid = '1' then
                    R_cache_request.address <= cpu_bus_req.address;
                    R_cache_request.data_size <= cpu_bus_req.data_size;
                    R_cache_request.cancelled <= '0';
                    R_cache_request.valid <= '1';

                    if cpu_bus_req.address(ADDRESS_WIDTH - 1 downto ADDRESS_WIDTH - 4) = UNCACHED_ADDR_RANGE and
                      ENABLE_UNCACHED_ADDR_RANGE = true then
                        R_cache_request.cacheable <= '0';
                    else
                        R_cache_request.cacheable <= '1';
                    end if;

                    if ENABLE_WRITE = true then
                        R_cache_request.rw <= cpu_bus_req.rw;
                        R_cache_request.data <= cpu_bus_req.data;
                    else
                        R_cache_request.rw <= '0';
                        R_cache_request.data <= (others => '0');
                    end if;
                -- Current request done, no new request
                elsif stall /= '1' and cpu_bus_req.valid /= '1' then
                    R_cache_request.valid <= '0';
                else
                    if cpu_bus_req.cancel = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- FIND IF THERE IS A HIT IN ANY CACHELINE IN BLOCK
    process(R_cache_request.valid, R_cache_request.address, cache_block_read, cache_block_hit_slot_index)
    begin
        cache_hit <= '0';
        cache_block_hit_slot_index <= (others => '0');
        if R_cache_request.valid = '1' then
            for i in 0 to ASSOCIATIVITY - 1 loop
                if F_get_tag_vector(R_cache_request.address) = cache_block_read(i).tag and cache_block_read(i).state /= CL_STATE_INVALID then
                    cache_block_hit_slot_index <= to_unsigned(i, C_cacheline_index_size);
                    cache_hit <= '1';
                end if;
            end loop;
        end if;

        cacheline_read <= cache_block_read(to_integer(cache_block_hit_slot_index));
    end process;

    -- LOCATE WORD IN CACHELINE WITH HIT
    process(cacheline_read, R_cache_request.address)
    begin
        cache_read_word <= (others => '0');
        for i in 0 to WORDS_PER_CACHELINE - 1 loop
            if F_get_word_index(R_cache_request.address) = i then
                cache_read_word <= cacheline_read.data(8 * BYTES_PER_WORD * (i + 1) - 1 downto 8 * BYTES_PER_WORD * i);
            end if;
        end loop;
    end process;
    
    -- CACHELINE MODIFICATION LOGIC
    process(R_cache_request)
    begin
        cacheline_modify_byte_enable <= (others => '0');
        cacheline_modify_data_write <= (others => '0');
        if ENABLE_WRITE = true then
            -- Generate cacheline write byte mask
            case R_cache_request.data_size is
            when "00" =>        -- BYTE (8-bit)
                for i in 0 to C_cacheline_size_bytes - 1 loop
                    if F_get_byte_index(R_cache_request.address) = i then
                        cacheline_modify_byte_enable(i) <= '1';
                        cacheline_modify_data_write(8 * (i + 1) - 1 downto 8 * i) <= R_cache_request.data(7 downto 0);
                    end if;
                end loop;
            when "01" =>        -- HALF-WORD (16-bit)
                for i in 0 to C_cacheline_size_bytes / 2 - 1 loop
                    if F_get_halfword_index(R_cache_request.address) = i then
                        cacheline_modify_byte_enable(2 * i) <= '1';
                        cacheline_modify_byte_enable(2 * i + 1) <= '1';
                        cacheline_modify_data_write(16 * (i + 1) - 1 downto 16 * i) <= R_cache_request.data(15 downto 0);
                    end if;
                end loop;
            when "10" =>        -- WORD (32-bit)
                for i in 0 to C_cacheline_size_bytes / 4 - 1 loop
                    if F_get_word_index(R_cache_request.address) = i then
                        cacheline_modify_byte_enable(4 * i) <= '1';
                        cacheline_modify_byte_enable(4 * i + 1) <= '1';
                        cacheline_modify_byte_enable(4 * i + 2) <= '1';
                        cacheline_modify_byte_enable(4 * i + 3) <= '1';
                        cacheline_modify_data_write(32 * (i + 1) - 1 downto 32 * i) <= R_cache_request.data(31 downto 0);
                    end if;
                end loop;
            when others =>
            end case;
        end if;
    end process;

    -- CACHE STATE MACHINE TRANSITION CONTROL
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_cache_control_sm <= INITIALIZE;
                R_init_cacheline_counter <= (others => '0');
                R_random_selector <= (others => '0');
                R_uncacheable_read_data_valid <= '0';
            else
                if ASSOCIATIVITY = 1 then
                    R_random_selector <= (others => '0');
                else
                    R_random_selector <= R_random_selector + 1;
                end if;

                case R_cache_control_sm is
                when NORMAL =>
                    if R_cache_request.valid = '1' then
                        if R_cache_request.cacheable = '1' then
                            if cache_hit = '0' then
                                if cacheio_req_ready = '1' then
                                    --if cache_block_full = '1' and ENABLE_WRITE = true then
                                    if cache_block_needs_eviction = '1' and ENABLE_WRITE = true then
                                        R_cache_control_sm <= STALL_IO_EVICT;
                                    else
                                        R_cache_control_sm <= STALL_IO_FETCH;
                                    end if;
                                end if;
                            else
                                if R_cache_request.rw = '1' then
                                    R_cache_control_sm <= CYCLE_DELAY;
                                end if;
                            end if;
                        else
                            if R_cache_request.rw = '0' then
                                if R_uncacheable_read_data_valid /= '1' then
                                    R_cache_control_sm <= STALL_IO_FETCH;
                                end if;
                            end if;
                        end if;
                    end if;

                    if R_uncacheable_read_data_valid = '1' then
                        R_uncacheable_read_data_valid <= '0';
                    end if;
                when INITIALIZE =>      -- Initializes all cacheline states to INVALID (empty)
                    if R_init_cacheline_counter = C_cache_num_blocks - 1 then
                        R_cache_control_sm <= NORMAL;
                    end if;

                    R_init_cacheline_counter <= R_init_cacheline_counter + 1;
                when STALL_IO_FETCH =>
                    -- Wait until I/O is done
                    if cacheio_resp_valid = '1' and cacheio_resp_ready = '1' then
                        if R_cache_request.cacheable = '0' then
                            R_uncacheable_read_data <= cacheio_resp_data(C_cacheline_data_size - 1 downto C_cacheline_data_size - C_cacheline_word_size);
                            R_uncacheable_read_data_valid <= '1';
                            R_cache_control_sm <= NORMAL;
                        else
                            R_cache_control_sm <= CYCLE_DELAY;
                        end if;
                    end if;
                when STALL_IO_EVICT =>
                    if cacheio_resp_valid = '1' and cacheio_resp_ready = '1' then
                        R_cache_control_sm <= CYCLE_DELAY;
                    end if;
                when CYCLE_DELAY =>
                    R_cache_control_sm <= NORMAL;
                when others =>
                end case;
            end if;
        end if;
    end process;
    
    -- TODO: HANDLE CASE WHEN NEXT REQUEST READS THE CACHELINE THAT WAS JUST MODIFIED IN THE PREVIOUS CYCLE
    -- CACHE STATE MACHINE OUTPUT CONTROL
    process(R_cache_control_sm, R_init_cacheline_counter, R_cache_request, cpu_bus_req.address, cache_hit,
        cacheio_resp_address, cacheline_mem_write_block_addr, cacheio_resp_data, cacheio_resp_valid, cacheio_resp_ready,
        cache_read_word, cacheline_modify_byte_enable, cacheline_read, cache_block_needs_eviction, R_uncacheable_read_data_valid,
        cacheio_req_ready, clalloc_allocated_cacheline_index, cacheline_evict, cache_block_hit_slot_index)
    begin
        stall <= '0';

        cacheio_req_address <= R_cache_request.address;
        cacheio_req_data_size <= "10";
        cacheio_req_data <= cacheline_evict.data;
        cacheio_req_noncacheable <= '0';
        cacheio_req_rw <= '0';
        cacheio_req_valid <= '0';
        cacheio_resp_ready <= '0';

        cacheline_mem_read_addr <= F_get_block_vector(cpu_bus_req.address);

        cacheline_mem_write_block_addr <= F_get_block_vector(cacheio_resp_address);
        cacheline_mem_write_data <= cacheio_resp_data;
        cacheline_mem_byte_enable <= (others => '1');
        cacheline_mem_write_tag <= F_get_tag_vector(cacheio_resp_address);
        cacheline_mem_write_state <= CL_STATE_INVALID;
        cacheline_mem_write_slot_index  <= (others => '0');
        cacheline_mem_write_data_valid <= '0';
        cacheline_mem_write_tag_valid <= '0';
        cacheline_mem_write_state_valid <= '0';

        if R_cache_request.cacheable = '1' then
            cpu_bus_resp.data <= cache_read_word;
        else
            cpu_bus_resp.data <= R_uncacheable_read_data;
        end if;
        cpu_bus_resp.address <= R_cache_request.address;
        cpu_bus_resp.rw <= R_cache_request.rw;
        cpu_bus_resp.valid <= '0';
        case R_cache_control_sm is
        when NORMAL =>
            if R_cache_request.cacheable = '0' then
                cacheio_req_address <= R_cache_request.address;
                cacheio_req_data(C_cacheline_data_size - 1 downto C_cacheline_data_size - C_cacheline_word_size)
                  <= R_cache_request.data;
                cacheio_req_data_size <= R_cache_request.data_size;
                cacheio_req_rw <= R_cache_request.rw;
                cacheio_req_noncacheable <= '1';
                cacheio_req_valid <= not R_uncacheable_read_data_valid and R_cache_request.valid;
                if R_cache_request.rw = '0' then
                    if R_uncacheable_read_data_valid /= '1' and R_cache_request.valid = '1' then
                        stall <= '1';
                    end if;
                else
                    -- Wait until cache I/O unit accpets the request
                    if cacheio_req_ready /= '1' then
                        stall <= '1';
                    end if;
                end if;
            else
                if R_cache_request.valid = '1' then
                     if cache_hit = '1' then
                        if ENABLE_WRITE = true and
                          R_cache_request.rw = '1' then
                            cacheline_mem_write_data <= cacheline_modify_data_write;
                            cacheline_mem_write_block_addr <= F_get_block_vector(R_cache_request.address);
                            cacheline_mem_byte_enable <= cacheline_modify_byte_enable;
                            cacheline_mem_write_state <= CL_STATE_MODIFIED;
                            cacheline_mem_write_slot_index <= cache_block_hit_slot_index;
                            cacheline_mem_write_data_valid <= '1';
                            cacheline_mem_write_state_valid <= '1';
                        end if;
                    else
                        if ENABLE_WRITE = true then
                            if cache_block_needs_eviction = '1' then
                                cacheio_req_address <= (others => '0');
                                cacheio_req_address(ADDRESS_WIDTH - 1 downto ADDRESS_WIDTH - C_cacheline_tag_size - C_cache_block_index_size)
                                  <= cacheline_evict.tag & F_get_block_vector(R_cache_request.address);
                                cacheio_req_rw <= '1';

                                cacheline_mem_write_block_addr <= F_get_block_vector(R_cache_request.address);
                                cacheline_mem_write_state <= CL_STATE_INVALID;
                                cacheline_mem_write_slot_index <= clalloc_allocated_cacheline_index;
                                cacheline_mem_write_state_valid <= '1';
                            end if;
                            cacheio_req_valid <= '1';
                            stall <= '1';
                        else
                            cacheio_req_valid <= '1';
                            stall <= '1';
                        end if;
                    end if;
                end if;
            end if;
            cpu_bus_resp.valid <= R_cache_request.valid and not R_cache_request.cancelled and
              (cache_hit or (not R_cache_request.cacheable and R_uncacheable_read_data_valid));
            cacheio_resp_ready <= '1';
            R_cache_response.valid <= '0';
        when INITIALIZE =>
            cacheline_mem_write_block_addr <= std_logic_vector(R_init_cacheline_counter);
            cacheline_mem_write_state_valid <= '1';
            stall <= '1';
        when STALL_IO_FETCH =>
            cacheline_mem_write_slot_index  <= clalloc_allocated_cacheline_index;
            cacheline_mem_write_state <= CL_STATE_EXCLUSIVE;
            if R_cache_request.cacheable = '1' then
                cacheline_mem_write_data_valid <= cacheio_resp_valid and cacheio_resp_ready;
                cacheline_mem_write_tag_valid <= cacheio_resp_valid and cacheio_resp_ready;
                cacheline_mem_write_state_valid <= cacheio_resp_valid and cacheio_resp_ready;
            end if;

            stall <= '1';
            cacheio_resp_ready <= '1';
        when STALL_IO_EVICT =>
            stall <= '1';
            cacheio_resp_ready <= '1';
        when CYCLE_DELAY =>
            cacheline_mem_read_addr <= F_get_block_vector(R_cache_request.address);
            stall <= '1';
        when others =>
        end case;
    end process;
    cpu_bus_resp.ready <= not stall;
end rtl;