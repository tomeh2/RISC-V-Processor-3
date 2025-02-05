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
        SIZE_BYTES: natural                    -- MUST BE POWER OF 2
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
    signal cacheline_mem_write_data: std_logic_vector(C_cacheline_size - 1 downto 0);
    signal cacheline_mem_read_addr: std_logic_vector(C_cache_block_index_size - 1 downto 0);
    signal cacheline_mem_write_addr: std_logic_vector(C_cache_block_index_size - 1 downto 0);
    signal cacheline_mem_write_enable: std_logic_vector(C_cachelines_per_block - 1 downto 0);

    type T_cache_request is record
        address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0); 
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
    type T_cache_control_sm is (INITIALIZE, NORMAL, STALL_CACHE_IO_NOT_READY, STALL_IO);
    signal R_cache_control_sm: T_cache_control_sm;

    signal R_init_cacheline_counter: unsigned(C_cache_block_index_size - 1 downto 0);
    signal cacheline_read: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal R_cache_request: T_cache_request;
    signal R_cache_response: T_cache_response;

    signal cache_hit: std_logic;

    signal R_random_selector: unsigned(C_cacheline_index_size - 1 downto 0);

    signal cache_read_word: std_logic_vector(C_cacheline_word_size - 1 downto 0);

    -- CACHE BLOCK SIGNALS
    signal cache_block_read: T_cache_block;
    signal cache_block_full: std_logic;
    signal cache_block_free_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal cache_block_writeback_index: unsigned(C_cacheline_index_size - 1 downto 0);
    signal cache_block_read_index: unsigned(C_cacheline_index_size - 1 downto 0);

    -- CACHE IO SIGNALS
    signal cacheio_req_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal cacheio_req_data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal cacheio_req_rw: std_logic;
    signal cacheio_req_valid: std_logic;
    signal cacheio_resp_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal cacheio_resp_data: std_logic_vector(C_cacheline_data_size - 1 downto 0);
    signal cacheio_resp_ready: std_logic;
    signal cacheio_resp_valid: std_logic;

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

    function F_get_block_integer(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_block_vector(address)));
    end function;

    function F_get_word_integer(address: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(F_get_word_vector(address)));
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
             cacheio_req_rw => cacheio_req_rw,
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
        cacheline_mem_write_enable(i) <= '1' when cache_block_writeback_index = i and cacheio_resp_valid = '1' else '0';
        I_cache_ram_data: entity work.bram
        generic map(
            WORD_LENGTH => C_cacheline_data_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_addr,
            write_enable => cacheline_mem_write_enable(i),
            data_write => cacheio_resp_data,
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).data
        );  
        
        I_cache_ram_tags: entity work.bram
        generic map(
            WORD_LENGTH => C_cacheline_tag_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_addr,
            write_enable => cacheline_mem_write_enable(i),
            data_write => F_get_tag_vector(cacheio_resp_address),
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).tag
        );

        I_cache_ram_states: entity work.bram
        generic map(
            WORD_LENGTH => C_cacheline_state_size,
            NUM_WORDS => C_cache_num_blocks
        )
        port map(
            clk => clk,
            reset => reset,
            
            addr_write => cacheline_mem_write_addr,
            write_enable => cacheline_mem_write_enable(i),
            data_write => CL_STATE_EXCLUSIVE,
            addr_read => cacheline_mem_read_addr,
            data_read => cache_block_read(i).state
        );
    end generate;

    -- This process selects the cacheline inside of a block that will be used to store the
    -- fetched data. It prioritizes empty cachelines first and if there are none it
    -- just picks one at random (for now).
    process(cache_block_read, R_random_selector, cache_block_full, cache_block_free_index)
    begin
        cache_block_full <= '1';
        cache_block_free_index <= (others => '0');
        for i in 0 to ASSOCIATIVITY - 1 loop
            if cache_block_read(i).state = CL_STATE_INVALID then
                cache_block_free_index <= to_unsigned(i, C_cacheline_index_size);
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
                        if cacheio_resp_ready = '1' then
                            R_cache_control_sm <= STALL_IO;
                        else
                            R_cache_control_sm <= STALL_CACHE_IO_NOT_READY;
                        end if;
                    end if;
                when INITIALIZE =>      -- Initializes all cacheline states to INVALID (empty)
                    if R_init_cacheline_counter = C_cache_num_blocks - 1 then
                        R_cache_control_sm <= NORMAL;
                    end if;

                    R_init_cacheline_counter <= R_init_cacheline_counter + 1;
                when STALL_CACHE_IO_NOT_READY =>
                    if cacheio_resp_ready = '1' then
                        R_cache_control_sm <= NORMAL;
                    end if;
                when STALL_IO =>
                    if cache_hit = '1' then
                        R_cache_control_sm <= NORMAL;
                    else
                    end if;
                when others =>
                end case;
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_cache_request.valid <= '0';
            else
                if stall_out /= '1' then
                    R_cache_request.address <= cpu_bus_req.address;
                    R_cache_request.rw <= cpu_bus_req.rw;
                    R_cache_request.cancelled <= '0';
                    R_cache_request.valid <= cpu_bus_req.valid;
                else
                    if cancel_all = '1' then
                        R_cache_request.cancelled <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(R_cache_request.valid, R_cache_request.address, cache_block_read, cache_block_read_index)
    begin
        cache_hit <= '0';
        cache_block_read_index <= (others => '0');
        if R_cache_request.valid = '1' then
            for i in 0 to ASSOCIATIVITY - 1 loop
                if F_get_tag_vector(R_cache_request.address) = cache_block_read(i).tag and cache_block_read(i).state /= CL_STATE_INVALID then
                    cache_block_read_index <= to_unsigned(i, C_cacheline_index_size);
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
            if F_get_word_integer(R_cache_request.address) = i then
                cache_read_word <= cacheline_read(8 * BYTES_PER_WORD * (i + 1) - 1 downto 8 * BYTES_PER_WORD * i);
            end if;
        end loop;
    end process;
    
    process(R_cache_control_sm, R_init_cacheline_counter, R_cache_request, cpu_bus_req.address, cache_hit,
        cacheio_resp_address)
    begin
        stall_out <= '0';
        cacheio_req_address <= R_cache_request.address;
        cacheio_req_valid <= '0';
        cacheline_mem_read_addr <= F_get_block_vector(cpu_bus_req.address);
        cacheline_mem_write_addr <= F_get_block_vector(cacheio_resp_address);
        case R_cache_control_sm is
        when NORMAL =>
            if R_cache_request.valid = '1' and
                 cache_hit = '0' then
                cacheline_mem_read_addr <= F_get_block_vector(R_cache_request.address);
                cacheio_req_valid <= '1';
                stall_out <= '1';
            end if;
            R_cache_response.valid <= '0';
        when INITIALIZE =>
            stall_out <= '1';
        when STALL_CACHE_IO_NOT_READY =>
            stall_out <= '1';
        when STALL_IO =>
            if cache_hit = '1' then
                cacheline_mem_read_addr <= F_get_block_vector(cpu_bus_req.address);
            else
                cacheline_mem_read_addr <= F_get_block_vector(R_cache_request.address);
            end if;
            stall_out <= '0' when cache_hit = '1' else '1';
        when others =>
        end case;
    end process;

    cpu_bus_resp.address <= R_cache_request.address;
    cpu_bus_resp.data <= cache_read_word;
    cpu_bus_resp.valid <= R_cache_request.valid and not R_cache_request.cancelled and cache_hit;
end rtl;