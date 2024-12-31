library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity top_sim is

end top_sim;

architecture Behavioral of top_sim is
    constant CLK_PERIOD : time := 10ns;

    signal clk, reset : std_logic;
    signal tx, rx : std_logic;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;
    
    process(clk)
    begin
        
    end process;

    process
    begin
        reset <= '0';
        wait for CLK_PERIOD * 10;
        reset <= '1';
        wait;
    end process;

    process
    begin
        tx <= '1';
        wait for 1us;
        tx <= '0';
        wait for 4.34us;
        tx <= '0';
        wait for 4.34us;
        tx <= '1';
        wait for 4.34us;
        tx <= '0';
        wait for 4.34us;
        tx <= '1';
        wait for 4.34us;
        tx <= '0';
        wait for 4.34us;
        tx <= '1';
        wait for 4.34us;
        tx <= '0';
        wait for 4.34us;
        tx <= '1';
        wait for 4.34us;
    end process;

    I_top : entity work.top
    port map(CLK100MHZ => clk,
             CPU_RESETN => reset,
             UART_TXD => tx,
             UART_RXD => rx,
             SW => X"AAAA",
             LED => open);
end Behavioral;
