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
        procedure F_uart_send(constant char: in std_logic_vector(7 downto 0); signal uart_tx: out std_logic) is
            constant C_baud_time: time := 8.68us;        -- 115200 Baud
        begin
            uart_tx <= '0';
            wait for C_baud_time;
            for i in 0 to 7 loop
                uart_tx <= char(i);
                wait for C_baud_time;
            end loop;
            uart_tx <= '1';
            wait for C_baud_time;
        end procedure;
    begin
        tx <= '1';
        wait for 2ms;
        F_uart_send(X"0D", tx);
        wait for 500us;
        F_uart_send(X"70", tx);
        wait for 250us;
        F_uart_send(X"72", tx);
        wait for 250us;
        F_uart_send(X"6F", tx);
        wait for 250us;
        F_uart_send(X"67", tx);
        wait for 250us;
        F_uart_send(X"0D", tx);
    end process;

    I_top : entity work.top
    port map(CLK100MHZ => clk,
             CPU_RESETN => reset,
             UART_TXD => tx,
             UART_RXD => rx,
             SW => X"AAAA",
             LED => open,
             TMP_INT => '0',
             TMP_CT => '0');
end Behavioral;
