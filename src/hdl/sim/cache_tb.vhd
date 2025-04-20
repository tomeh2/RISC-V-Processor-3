library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity cache_tb is

end cache_tb;

architecture Behavioral of cache_tb is
    constant CLK_PERIOD : time := 10ns;
    constant RST_DURATION : time := CLK_PERIOD * 10;

    signal clk, rst, rst_addr: std_logic;
    signal R_burst_cnt: unsigned(7 downto 0);
    
    type T_bus_sm is (IDLE, BUSY);
    signal R_bus_sm: T_bus_sm;
    signal nextaddr: std_logic;
    signal stall: std_logic;
    
    signal bus_req: T_bus_request;
    signal bus_resp: T_bus_response;
    signal bus_req2: T_bus_request;
    signal bus_resp2: T_bus_response;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    process
    begin
        rst_addr <= '0';
        rst <= '1';
        wait for RST_DURATION;
        rst <= '0';
        wait for 2us;
        rst_addr <= '1';
        wait for 10ns;
        rst_addr <= '0';
        wait;
    end process;

    
--    process(clk)
--    begin
--        if rising_edge(clk) then
--            if rst = '1' or rst_addr = '1' then
--                bus_req.address <= X"0000_0000";
--            else
--                if stall /= '1' then
--                    bus_req.address <= std_logic_vector(unsigned(bus_req.address) + 4);
--                end if;
--            end if;
--        end if;
--    end process;
    
    process
        procedure F_cache_gen_request(addr: std_logic_vector(31 downto 0); rw: std_logic; data_size: std_logic_vector(1 downto 0);
          data_write: std_logic_vector(31 downto 0) := X"0000_0000") is
        begin
            bus_req.address <= addr;
            bus_req.data <= data_write;
            bus_req.data_size <= data_size;
            bus_req.rw <= rw;
            bus_req.is_unsigned <= '0';
            bus_req.valid <= '1';
            wait for 100ps;
            if bus_resp.ready /= '1' then
                wait until bus_resp.ready = '1';
            end if;
            wait until rising_edge(clk);
            bus_req.address <= X"0000_0000";
            bus_req.data <= X"0000_0000";
            bus_req.data_size <= "00";
            bus_req.rw <= '0';
            bus_req.is_unsigned <= '0';
            bus_req.valid <= '0';
            if rw = '1' then
                wait for 100ps;
            else
                if bus_resp.valid /= '1' and rw = '0' then
                    wait until bus_resp.valid = '1';
                end if;
            end if;
        end procedure;
    begin
        bus_req.ready <= '1';
        wait for 5us;
        F_cache_gen_request(X"0000_0000", '0', "10");
        F_cache_gen_request(X"0000_0004", '0', "10");
        F_cache_gen_request(X"0000_0008", '0', "10");
        F_cache_gen_request(X"0000_000C", '0', "10");
        F_cache_gen_request(X"0000_0010", '0', "10");
        F_cache_gen_request(X"0000_0014", '0', "10");
        F_cache_gen_request(X"0000_0018", '0', "10");
        F_cache_gen_request(X"0000_001C", '0', "10");
        F_cache_gen_request(X"0000_0020", '0', "10");
        F_cache_gen_request(X"0000_0024", '0', "10");
        F_cache_gen_request(X"0000_0028", '0', "10");
        F_cache_gen_request(X"0000_002C", '0', "10");
        F_cache_gen_request(X"0000_0030", '0', "10");
        F_cache_gen_request(X"0000_0034", '0', "10");
        F_cache_gen_request(X"0000_0038", '0', "10");
        F_cache_gen_request(X"0000_003C", '0', "10");
        wait for 1us;
        F_cache_gen_request(X"0000_0000", '1', "10", X"1234_5678");
        F_cache_gen_request(X"0000_0004", '1', "10", X"0105_AB03");
        F_cache_gen_request(X"0000_0008", '1', "10", X"7654_3210");
        F_cache_gen_request(X"0000_000C", '1', "10", X"ABCD_EF01");
        wait for 1us;
        F_cache_gen_request(X"0000_0000", '1', "01", X"1234_5678");
        F_cache_gen_request(X"0000_0002", '1', "01", X"1234_4632");
        F_cache_gen_request(X"0000_0004", '1', "01", X"1234_1234");
        F_cache_gen_request(X"0000_0006", '1', "01", X"1234_4312");
        F_cache_gen_request(X"0000_0008", '1', "01", X"1234_6542");
        F_cache_gen_request(X"0000_000A", '1', "01", X"1234_ABC3");
        F_cache_gen_request(X"0000_000C", '1', "01", X"1234_1231");
        F_cache_gen_request(X"0000_000E", '1', "01", X"1234_7692");
        wait for 1us;
        F_cache_gen_request(X"0000_0000", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0001", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0002", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0003", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0004", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0005", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0006", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0007", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0008", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_0009", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000A", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000B", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000C", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000D", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000E", '1', "00", X"1234_5678");
        F_cache_gen_request(X"0000_000F", '1', "00", X"1234_5678");
        wait for 1us;
        F_cache_gen_request(X"0000_0010", '1', "10");
        F_cache_gen_request(X"0000_0020", '1', "10");
        F_cache_gen_request(X"0000_0030", '1', "10");
        wait for 10us;
        F_cache_gen_request(X"0000_0040", '0', "10");
        wait for 10us;
        F_cache_gen_request(X"F000_0000", '0', "10");
        F_cache_gen_request(X"F000_0000", '1', "10", X"DEFF_DABA");
        F_cache_gen_request(X"F000_0042", '0', "01");
        F_cache_gen_request(X"F000_0042", '1', "01", X"4219_ABCD");
        F_cache_gen_request(X"F000_0101", '0', "00");
        F_cache_gen_request(X"F000_0101", '1', "00", X"DBCA_4321");
        wait;
    end process;
    
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                R_bus_sm <= IDLE;
                bus_resp2.data <= X"0000_0000";
            else
                nextaddr <= '0';
                case R_bus_sm is
                when IDLE =>
                    if bus_req2.valid = '1' then
                        R_bus_sm <= BUSY;
                        R_burst_cnt <= bus_req2.burst_len;
                    end if;
                when BUSY =>
                    if R_burst_cnt = 0 then
                        R_bus_sm <= IDLE;
                        bus_resp2.data <= std_logic_vector(unsigned(bus_resp2.data) + 1);
                    else
                        R_burst_cnt <= R_burst_cnt - 1;
                        bus_resp2.data <= std_logic_vector(unsigned(bus_resp2.data) + 1);
                    end if;
                end case;
            end if;
        end if;
    end process;

    bus_resp2.valid <= '1' when R_bus_sm = BUSY else '0';

    I_cache: entity work.cache
    generic map(ENABLE_WRITE => true,
                ENABLE_UNCACHED_ADDR_RANGE => true,
                UNCACHED_ADDR_RANGE => X"F",
                ADDRESS_WIDTH => 32,
                ASSOCIATIVITY => 1,
                BYTES_PER_WORD => 4,
                WORDS_PER_CACHELINE => 4,
                SIZE_BYTES => 512)
    port map(clk => clk,
             reset => rst,
             cpu_bus_req => bus_req,
             cpu_bus_resp => bus_resp,
             ext_bus_req => bus_req2,
             ext_bus_resp => bus_resp2);
end Behavioral;
