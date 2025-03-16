library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity digital_filter_tb is

end digital_filter_tb;

architecture Behavioral of digital_filter_tb is
    constant CLK_PERIOD : time := 10ns;
    
    signal clk, rst: std_logic;
    signal delay: std_logic_vector(7 downto 0);
    signal din, dout_gf, dout_dbf: std_logic;
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
        delay <= X"20";
        din <= '0';
        wait for 1us;
        -- No glitches / bounces
        din <= '1';
        wait for 1us;
        -- 1 Bounce / glitch, return to initial
        din <= '0';
        wait for 100ns;
        din <= '1';
        wait for 1us;
        -- Multiple bounces / glitches, switch to 0
        din <= '0';
        wait for 50ns;
        din <= '1';
        wait for 50ns;
        din <= '0';
        wait for 100ns;
        din <= '1';
        wait for 60ns;
        din <= '0';
        wait;
    end process;
    
    uut_glitch: entity work.digital_filter
    generic map(
        DEBOUNCER => false,
        DELAY_WIDTH_BITS => 8
    )
    port map(
        clk => clk,
        delay => delay,
        din => din,
        dout => dout_gf
    );

    uut_debouncer: entity work.digital_filter
    generic map(
        DEBOUNCER => true,
        DELAY_WIDTH_BITS => 8
    )
    port map(
        clk => clk,
        delay => delay,
        din => din,
        dout => dout_dbf
    );
end Behavioral;
