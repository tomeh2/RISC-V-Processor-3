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

    signal adr_o : std_logic_vector(31 downto 0);
    signal dat_i : std_logic_vector(31 downto 0);
    signal dat_o : std_logic_vector(31 downto 0);
    signal we_o : std_logic;
    signal sel_o : std_logic_vector(3 downto 0);
    signal stb_o : std_logic;
    signal ack_i : std_logic;
    signal cyc_o : std_logic;
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
             
    wb_cntrlr_inst : entity work.wishbone_bus_controller
    port map(bus_req => bus_req,
             bus_resp => bus_resp,
             bus_ready => bus_ready,

             adr_o => adr_o,
             dat_i => dat_i,
             dat_o => dat_o,
             we_o => we_o,
             sel_o => sel_o,
             stb_o => stb_o,
             ack_i => ack_i,
             cyc_o => cyc_o,

             clk => clk,
             reset => reset);
             
    I_rom : entity work.rom
    generic map(C_size_kb => 4)
    port map(clk => clk,
             reset => reset,
             wb_addr => adr_o,
             wb_rdata => dat_i,
             wb_stb => stb_o,
             wb_cyc => cyc_o,
             wb_ack => ack_i);
end Behavioral;
