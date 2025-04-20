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
        cacheio_req_data_size: in std_logic_vector(1 downto 0);
        cacheio_req_noncacheable: in std_logic;
        cacheio_req_rw: in std_logic;
        cacheio_req_ready: out std_logic;
        cacheio_req_valid: in std_logic;

        cacheio_resp_address: out std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
        cacheio_resp_data: out std_logic_vector(CACHELINE_DATA_WIDTH - 1 downto 0);
        cacheio_resp_ready: in std_logic;
        cacheio_resp_valid: out std_logic;

        external_bus_req: out T_wishbone_req;
        external_bus_resp: in T_wishbone_resp
    );
end cache_io;

architecture rtl of cache_io is
    constant C_address_msb: natural := ADDRESS_WIDTH - 1;
    constant C_address_lsb: natural := F_min_bits(BYTES_PER_WORD) + F_min_bits(WORDS_PER_CACHELINE);

    type T_read_sm is (IDLE, READ, WRITE, RESPONSE);
    signal R_state: T_read_sm;
    signal R_address_response: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal R_address: std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
    signal R_data_size: std_logic_vector(1 downto 0);
    signal R_burst_len: unsigned(7 downto 0);
    signal R_burst_left: unsigned(7 downto 0);
    signal R_data: std_logic_vector(CACHELINE_DATA_WIDTH - 1 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_state <= IDLE;
            else
                case R_state is
                when IDLE =>
                    if cacheio_req_valid = '1' then
                        if cacheio_req_rw = '1' then
                            R_state <= WRITE;
                            R_data <= cacheio_req_data;
                        else
                            R_state <= READ;
                        end if;
                        R_address <= (others => '0');
                        R_address_response <= (others => '0');
                        if cacheio_req_noncacheable = '1' then
                            R_address <= cacheio_req_address;
                            R_address_response <= cacheio_req_address;
                            R_burst_len <= to_unsigned(0, 8);
                            R_burst_left <= to_unsigned(0, 8);
                            R_data_size <= cacheio_req_data_size;
                        else
                            R_address(C_address_msb downto C_address_lsb) <= cacheio_req_address(C_address_msb downto C_address_lsb);
                            R_address_response <= cacheio_req_address;
                            R_burst_len <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                            R_burst_left <= to_unsigned(WORDS_PER_CACHELINE - 1, 8);
                            R_data_size <= "10";
                        end if;
                    end if;
                when READ =>
                    if external_bus_resp.ack = '1' then
                        R_address <= std_logic_vector(unsigned(R_address) + 4);
                        for i in 0 to WORDS_PER_CACHELINE - 1 loop
                            if (WORDS_PER_CACHELINE - 1 - to_integer(R_burst_left)) = i then
                                R_data(BYTES_PER_WORD * 8 * (i + 1) - 1 downto BYTES_PER_WORD * 8 * i) <=
                                  external_bus_resp.dat;
                            end if;
                        end loop;
                        if R_burst_left = 0 then
                            R_state <= RESPONSE;
                        else
                            R_burst_left <= R_burst_left - 1;
                        end if;
                    end if;
                when WRITE =>
                    if external_bus_resp.ack = '1' then
                        R_address <= std_logic_vector(unsigned(R_address) + 4);
                        if R_burst_left = 0 then
                            R_state <= RESPONSE;
                        else
                            R_burst_left <= R_burst_left - 1;
                        end if;
                    end if;
                when RESPONSE =>
                    if cacheio_resp_ready = '1' and
                        cacheio_resp_valid = '1' then
                        R_state <= IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;

    process(R_address, R_address_response, R_data, R_state, R_burst_left, R_burst_len, R_data_size)
    begin
        external_bus_req.adr <= R_address;
        external_bus_req.dat <= (others => '0');
        external_bus_req.we <= '0';
        external_bus_req.stb <= '0';
        external_bus_req.cyc <= '0';

        cacheio_resp_address <= R_address_response;
        cacheio_resp_data <= R_data;
        cacheio_resp_valid <= '0';
        cacheio_req_ready <= '0';
        case R_state is
        when IDLE =>
            cacheio_req_ready <= '1';    
        when READ =>
            external_bus_req.stb <= '1';
            external_bus_req.cyc <= '1';
        when WRITE =>
            for i in 0 to WORDS_PER_CACHELINE - 1 loop
                if (WORDS_PER_CACHELINE - 1 - to_integer(R_burst_left)) = i then
                    external_bus_req.dat <=
                      R_data(BYTES_PER_WORD * 8 * (i + 1) - 1 downto BYTES_PER_WORD * 8 * i);
                end if;
            end loop;
            external_bus_req.stb <= '1';
            external_bus_req.cyc <= '1';
            external_bus_req.we <= '1';
        when RESPONSE =>
            cacheio_resp_valid <= '1';
        end case;
    end process;

    P_wb_data_mask : process(R_data_size, R_address)
    begin
        external_bus_req.sel <= (others => '0');
        case R_data_size is
        when "00" =>
            case R_address(1 downto 0) is
            when "00" =>
                external_bus_req.sel <= "0001";
            when "01" =>
                external_bus_req.sel <= "0010";
            when "10" =>
                external_bus_req.sel <= "0100";
            when "11" =>
                external_bus_req.sel <= "1000";
            when others =>
            end case;
        when "01" =>
            case R_address(1) is
            when '0' =>
                external_bus_req.sel <= "0011";
            when '1' =>
                external_bus_req.sel <= "1100";
            when others =>
            end case;
        when "10" =>
            external_bus_req.sel <= "1111";
        when others =>
        end case; 
    end process;
end rtl;
