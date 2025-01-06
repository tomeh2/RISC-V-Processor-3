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

    bus_req.rw <= '0';
    bus_req.is_unsigned <= '0';
    bus_req.valid <= '1';
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or rst_addr = '1' then
                bus_req.address <= X"0000_0000";
            else
                if stall /= '1' then
                    bus_req.address <= std_logic_vector(unsigned(bus_req.address) + 4);
                end if;
            end if;
        end if;
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
    generic map(ADDRESS_WIDTH => 32,
                ASSOCIATIVITY => 4,
                BYTES_PER_WORD => 4,
                WORDS_PER_CACHELINE => 8,
                NUM_BLOCKS => 8)
    port map(clk => clk,
             reset => rst,
             stall_out => stall,
             bus_req => bus_req,
             bus_resp => bus_resp,
             bus_req2 => bus_req2,
             bus_resp2 => bus_resp2);
end Behavioral;
