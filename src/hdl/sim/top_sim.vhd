library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity top_sim is

end top_sim;

architecture Behavioral of top_sim is
    constant CLK_PERIOD : time := 10ns;

    signal clk, reset : std_logic;

    signal bus_req : T_bus_request;
    signal bus_resp : T_bus_response;
    signal bus_ready : std_logic;
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
        reset <= '1';
        wait for CLK_PERIOD * 10;
        reset <= '0';
        wait;
    end process;

    cpu_top_inst : entity work.cpu
    port map(bus_req     => bus_req,
             bus_resp    => bus_resp,
             bus_ready   => bus_ready,
             clk         => clk,
             reset       => reset);
end Behavioral;
