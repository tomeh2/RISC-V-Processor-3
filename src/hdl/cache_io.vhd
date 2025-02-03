library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity cache_io is
    generic(
        ADDRESS_WIDTH: natural;
        CACHELINE_DATA_WIDTH: natural;
        BYTES_PER_WORD: natural;               -- MUST BE POWER OF 2
        WORDS_PER_CACHELINE: natural           -- MUST BE POWER OF 2
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        cacheio_req_address: in std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
        cacheio_req_data: in std_logic_vector(CACHELINE_DATA_WIDTH - 1 downto 0);
        cacheio_req_rw: in std_logic;
        cacheio_req_valid: in std_logic;

        cacheio_resp_address: out std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
        cacheio_resp_data: out std_logic_vector(CACHELINE_DATA_WIDTH - 1 downto 0);
        cacheio_resp_ready: out std_logic;
        cacheio_resp_valid: out std_logic;

        external_bus_req: out T_bus_request;
        external_bus_resp: in T_bus_response
    );
end cache_io;

architecture rtl of cache_io is
    constant C_address_msb: natural := ADDRESS_WIDTH - 1;
    constant C_address_lsb: natural := F_min_bits(BYTES_PER_WORD) + F_min_bits(WORDS_PER_CACHELINE);

    type T_read_sm is (IDLE, FETCHING, RESPONSE);
    signal R_read_sm: T_read_sm;
    signal R_read_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal R_read_burst_len: unsigned(7 downto 0);
    signal R_read_burst_left: unsigned(7 downto 0);
    signal R_read_data: std_logic_vector(CACHELINE_DATA_WIDTH - 1 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_read_sm <= IDLE;
            else
                case R_read_sm is
                when IDLE =>
                    if cacheio_req_valid = '1' then
                        R_read_sm <= FETCHING;
                        R_read_address <= (others => '0');
                        R_read_address(C_address_msb downto C_address_lsb) <= cacheio_req_address(C_address_msb downto C_address_lsb);
                        R_read_burst_len <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                        R_read_burst_left <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                    end if;
                when FETCHING =>
                    if external_bus_resp.valid = '1' then
                        for i in 0 to WORDS_PER_CACHELINE - 1 loop
                            if (WORDS_PER_CACHELINE - 1 - to_integer(R_read_burst_left)) = i then
                                R_read_data(BYTES_PER_WORD * 8 * (i + 1) - 1 downto BYTES_PER_WORD * 8 * i) <=
                                  external_bus_resp.data;
                            end if;
                        end loop;

                        R_read_burst_left <= R_read_burst_left - 1;
                        if R_read_burst_left = 0 then
                            R_read_sm <= RESPONSE;
                        end if;
                    end if;
                when RESPONSE =>
                    R_read_sm <= IDLE;
                end case;
            end if;
        end if;
    end process;

    process(R_read_address, R_read_data, R_read_sm)
    begin
        cacheio_resp_address <= R_read_address;
        cacheio_resp_data <= R_read_data;
        cacheio_resp_valid <= '0';
        cacheio_resp_ready <= '0';
        case R_read_sm is
        when IDLE =>
            cacheio_resp_ready <= '1';    
        when FETCHING =>
        when RESPONSE =>
            cacheio_resp_valid <= '1';
        end case;
    end process;

    external_bus_req.address <= R_read_address;
    external_bus_req.valid <= '1' when R_read_sm = FETCHING else '0';
    external_bus_req.data_size <= "10";
    external_bus_req.is_unsigned <= '1';
    external_bus_req.rw <= '0';
    external_bus_req.burst_len <= R_read_burst_len;
end rtl;
