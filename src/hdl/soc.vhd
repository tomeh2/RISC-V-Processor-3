library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity soc is
    port(
        clk: in std_logic;
        reset: in std_logic;
        sevseg_anodes: out std_logic_vector(7 downto 0);
        sevseg_cathodes: out std_logic_vector(7 downto 0);
        gpio_in: in std_logic_vector(31 downto 0);
        gpio_out: out std_logic_vector(31 downto 0);
        i2c1_sda: inout std_logic;
        i2c1_scl: inout std_logic;
        i2c2_sda: inout std_logic;
        i2c2_scl: inout std_logic;
        uart_tx: out std_logic;
        uart_rx: in std_logic;
        sda_debug: out std_logic;
        scl_debug: out std_logic
    );
end soc;

architecture rtl of soc is
    signal bus_req_fe: T_bus_request;
    signal bus_resp_fe: T_bus_response;
    signal bus_req_lsu: T_bus_request;
    signal bus_resp_lsu: T_bus_response;
    signal bus_ready: std_logic;

    signal wb_req: T_wishbone_req;
    signal wb_resp: T_wishbone_resp;

    signal rom_rdata: std_logic_vector(31 downto 0);
    signal rom_stb: std_logic;
    signal rom_ack: std_logic;

    signal ram_rdata: std_logic_vector(31 downto 0);
    signal ram_stb: std_logic;
    signal ram_ack: std_logic;

    signal uart_rdata: std_logic_vector(31 downto 0);
    signal uart_stb: std_logic;
    signal uart_ack: std_logic;

    signal sevseg_rdata: std_logic_vector(31 downto 0);
    signal sevseg_stb: std_logic;
    signal sevseg_ack: std_logic;

    signal gpio_rdata: std_logic_vector(31 downto 0);
    signal gpio_stb: std_logic;
    signal gpio_ack: std_logic;

    signal i2c1_rdata: std_logic_vector(31 downto 0);
    signal i2c1_stb: std_logic;
    signal i2c1_ack: std_logic;
    
    signal i2c2_rdata: std_logic_vector(31 downto 0);
    signal i2c2_stb: std_logic;
    signal i2c2_ack: std_logic;
begin
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
    generic map(C_size_kb => 16)
    port map(clk => clk,
             reset => reset,
             wb_addr => wb_req.adr,
             wb_rdata => rom_rdata,
             wb_stb => rom_stb,
             wb_cyc => rom_stb,
             wb_ack => rom_ack);

    I_ram : entity work.ram
    generic map(SIZE_KB => 128)
    port map(clk => clk,
             reset => reset,
             wb_addr => wb_req.adr(16 downto 2),
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
             wb_adr_i => wb_req.adr(2 downto 2),
             wb_dat_o => uart_rdata,
             wb_dat_i => wb_req.dat,
             wb_sel_i => wb_req.sel,
             wb_we_i => wb_req.we,
             wb_cyc_i => uart_stb,
             wb_stb_i => uart_stb,
             wb_ack_o => uart_ack,
             rx => uart_rx,
             tx => uart_tx);

    I_sevseg : entity work.sevseg
    port map(clk => clk,
             reset => reset,
             wb_adr_i => wb_req.adr(3 downto 2),
             wb_dat_o => sevseg_rdata,
             wb_dat_i => wb_req.dat,
             wb_sel_i => wb_req.sel,
             wb_we_i => wb_req.we,
             wb_cyc_i => sevseg_stb,
             wb_stb_i => sevseg_stb,
             wb_ack_o => sevseg_ack,
             anodes => sevseg_anodes,
             cathodes => sevseg_cathodes);

    I_gpio: entity work.gpio
    port map(clk => clk,
             reset => reset,
             wb_adr_i => wb_req.adr(2 downto 2),
             wb_dat_o => gpio_rdata,
             wb_dat_i => wb_req.dat,
             wb_sel_i => wb_req.sel,
             wb_we_i => wb_req.we,
             wb_cyc_i => gpio_stb,
             wb_stb_i => gpio_stb,
             wb_ack_o => gpio_ack,
             gpin => gpio_in,
             gpout => gpio_out);

    I_i2c1: entity work.i2c_controller
    generic map(SLAVE_ADDRESS => "0001000")
    port map(clk => clk,
             reset => reset,
             wb_adr_i => wb_req.adr(7 downto 0),
             wb_dat_o => i2c1_rdata,
             wb_dat_i => wb_req.dat,
             wb_sel_i => wb_req.sel,
             wb_we_i => wb_req.we,
             wb_cyc_i => i2c1_stb,
             wb_stb_i => i2c1_stb,
             wb_ack_o => i2c1_ack,
             i2c_sda => i2c1_sda,
             i2c_scl => i2c1_scl,
             sda_debug => sda_debug,
             scl_debug => scl_debug);

        your_instance_name : entity work.ila_1
PORT MAP (
	clk => clk,

	probe0 => wb_req.adr,
	probe1 => wb_req.dat,
	probe2(0) => wb_req.we,
	probe3 => wb_req.sel,
    probe4(0) => wb_req.stb,
    probe5(0) => wb_req.cyc,
    probe6 => wb_resp.dat,
    probe7(0) => wb_resp.ack
);

    process(wb_req.adr, wb_req.cyc, rom_rdata, rom_ack, uart_rdata, uart_ack,
            ram_rdata, ram_ack, sevseg_rdata, sevseg_ack, gpio_rdata, gpio_ack,
            i2c1_rdata, i2c1_ack)
    begin
        wb_resp.dat <= (others => '0');
        wb_resp.ack <= '0';
        rom_stb <= '0';
        uart_stb <= '0';
        ram_stb <= '0';
        sevseg_stb <= '0';
        gpio_stb <= '0';
        i2c1_stb <= '0';
        if wb_req.adr(31 downto 4) = X"FFFF_FFF" then
            wb_resp.dat <= uart_rdata;
            wb_resp.ack <= uart_ack;
            uart_stb <= wb_req.cyc;
        elsif wb_req.adr(31 downto 4) = X"FFFF_FFE" then
            wb_resp.dat <= sevseg_rdata;
            wb_resp.ack <= sevseg_ack;
            sevseg_stb <= wb_req.cyc;
        elsif wb_req.adr(31 downto 4) = X"FFFF_FFD" then
            wb_resp.dat <= gpio_rdata;
            wb_resp.ack <= gpio_ack;
            gpio_stb <= wb_req.cyc;
        elsif wb_req.adr(31 downto 8) = X"FFFF_FE" then
            wb_resp.dat <= i2c1_rdata;
            wb_resp.ack <= i2c1_ack;
            i2c1_stb <= wb_req.cyc;
        elsif wb_req.adr(31 downto 8) = X"FFFF_FD" then
            wb_resp.dat <= i2c2_rdata;
            wb_resp.ack <= i2c2_ack;
            i2c2_stb <= wb_req.cyc;
        elsif wb_req.adr(31 downto 28) = X"8" then
            wb_resp.dat <= ram_rdata;
            wb_resp.ack <= ram_ack;
            ram_stb <= wb_req.cyc;
        else
            wb_resp.dat <= rom_rdata;
            wb_resp.ack <= rom_ack;
            rom_stb <= wb_req.cyc;
        end if;
--        case wb_req.adr(31 downto 4) is
--        when X"0------" =>
--            wb_resp.dat <= rom_rdata;
--            wb_resp.ack <= rom_ack;
--            rom_stb <= wb_req.cyc;
--        when X"8------" =>
--            wb_resp.dat <= ram_rdata;
--            wb_resp.ack <= ram_ack;
--            ram_stb <= wb_req.cyc;
--        when X"FFFFFFE" =>
--            wb_resp.dat <= sevseg_rdata;
--            wb_resp.ack <= sevseg_ack;
--            sevseg_stb <= wb_req.cyc;
--        when X"FFFFFFF" =>
--            wb_resp.dat <= uart_rdata;
--            wb_resp.ack <= uart_ack;
--            uart_stb <= wb_req.cyc;
--        when others =>
--            wb_resp.ack <= '1';
--        end case;
    end process;
end rtl;
