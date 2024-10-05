library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity top_sim is

end top_sim;

-- TODO: Use instruction ID as destination register and then there is no need for an allocator?

architecture Behavioral of top_sim is
    constant CLK_PERIOD : time := 10ns;

    signal clk, reset : std_logic;

    signal bus_req_fe   : T_bus_request;
    signal bus_resp_fe  : T_bus_response;
    signal bus_req_lsu  : T_bus_request;
    signal bus_resp_lsu : T_bus_response;
    signal bus_ready : std_logic;

    signal wb_req : T_wishbone_req;
    signal wb_resp : T_wishbone_resp;

    signal rom_rdata : std_logic_vector(31 downto 0);
    signal rom_stb : std_logic;
    signal rom_ack : std_logic;

    signal ram_rdata : std_logic_vector(31 downto 0);
    signal ram_stb : std_logic;
    signal ram_ack : std_logic;

    signal uart_rdata : std_logic_vector(31 downto 0);
    signal uart_stb : std_logic;
    signal uart_ack : std_logic;
    signal uart_rx : std_logic;
    signal uart_tx : std_logic;
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
    port map(bus_req_fe     => bus_req_fe,
             bus_resp_fe    => bus_resp_fe,
             bus_req_lsu    => bus_req_lsu,
             bus_resp_lsu   => bus_resp_lsu,
             clk            => clk,
             reset          => reset);
             
    wb_cntrlr_inst : entity work.wishbone_bus_controller
    generic map(NUM_MASTERS => 2)
    port map(bus_req(0) => bus_req_fe,
             bus_req(1) => bus_req_lsu,
             bus_resp(0) => bus_resp_fe,
             bus_resp(1) => bus_resp_lsu,
             
             wb_req => wb_req,
             wb_resp => wb_resp,

             clk => clk,
             reset => reset);
             
    I_rom : entity work.rom
    generic map(C_size_kb => 4)
    port map(clk => clk,
             reset => reset,
             wb_addr => wb_req.adr,
             wb_rdata => rom_rdata,
             wb_stb => rom_stb,
             wb_cyc => rom_stb,
             wb_ack => rom_ack);

    I_ram : entity work.ram
    generic map(SIZE_KB => 4)
    port map(clk => clk,
             reset => reset,
             wb_addr => wb_req.adr(11 downto 2),
             wb_rdata => ram_rdata,
             wb_wdata => wb_req.dat,
             wb_stb => ram_stb,
             wb_cyc => ram_stb,
             wb_we => wb_req.we,
             wb_sel => wb_req.sel,
             wb_ack => ram_ack);

    I_uart : entity work.uart_16550
    port map(clk => clk,
             reset => reset,
             wb_adr_i => wb_req.adr(31 downto 2),
             wb_dat_o => uart_rdata,
             wb_dat_i => wb_req.dat,
             wb_sel_i => wb_req.sel,
             wb_we_i => wb_req.we,
             wb_cyc_i => uart_stb,
             wb_stb_i => uart_stb,
             wb_ack_o => uart_ack,
             rx => uart_rx,
             tx => uart_tx);

    process(wb_req.adr, wb_req.cyc, rom_rdata, rom_ack, uart_rdata, uart_ack, ram_rdata, ram_ack)
    begin
        wb_resp.dat <= (others => '0');
        wb_resp.ack <= '0';
        rom_stb <= '0';
        uart_stb <= '0';
        ram_stb <= '0';
        case wb_req.adr is
        when X"0---_----" =>
            wb_resp.dat <= rom_rdata;
            wb_resp.ack <= rom_ack;
            rom_stb <= wb_req.cyc;
        when X"FFFF_FFF-" =>
            wb_resp.dat <= uart_rdata;
            wb_resp.ack <= uart_ack;
            uart_stb <= wb_req.cyc;
        when X"8---_----" =>
            wb_resp.dat <= ram_rdata;
            wb_resp.ack <= ram_ack;
            ram_stb <= wb_req.cyc;
        when others =>
            wb_resp.dat <= (others => '0');
            wb_resp.ack <= '0';
        end case;
    end process;
end Behavioral;
