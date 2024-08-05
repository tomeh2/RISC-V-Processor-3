library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;
use WORK.SIM_PKG.ALL;

entity lsu_tb is
--  Port ( );
end lsu_tb;

architecture Behavioral of lsu_tb is
    constant MAX_CYCLES : integer := 100000;

    signal uop_in, uop_out, cdb : T_uop;
    signal port_agu : T_lsu_gen_port;
    
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

    signal stall_out : std_logic;
    signal stall_in : std_logic;
    signal clk : std_logic;
    signal rst : std_logic;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    rst <= '1', '0' after RST_DURATION;

    process
    begin
        -- GENERATE UOPS
        bus_ready <= '0';
        uop_in <= UOP_ZERO;
        cdb <= UOP_ZERO;
        port_agu.address_valid <= '0';
        port_agu.data_valid <= '0';
        wait until falling_edge(clk);
        wait for CLK_PERIOD * 10;
        for i in 0 to 10 loop
            uop_in.phys_src_reg_1 <= std_logic_vector(to_unsigned(i, PHYS_REG_ADDR_WIDTH));
            uop_in.phys_src_reg_2 <= std_logic_vector(to_unsigned(i, PHYS_REG_ADDR_WIDTH));
            uop_in.valid <= '1';
            wait until rising_edge(clk);
        end loop;
        uop_in.valid <= '0';
        wait until rising_edge(clk);
        -- GENERATE ADDR AND DATA
        port_agu.address_valid <= '1';
        port_agu.data_valid <= '1';
        port_agu.is_store <= '1';
        for i in 0 to 7 loop
            port_agu.address <= std_logic_vector(to_unsigned(4 * i + 65536, 32));
            port_agu.data <= X"1234_ABCD";
            port_agu.sq_tag <= to_unsigned(7 - i, 3);
            wait until rising_edge(clk);
        end loop;
        port_agu.address_valid <= '0';
        port_agu.data_valid <= '0';
        port_agu.is_store <= '0';
        -- SIMULATE BUS
        bus_ready <= '1';
        wait;
    end process;

    bus_cntrl : entity work.wishbone_bus_controller
    port map(bus_req    => bus_req,
             bus_resp   => bus_resp,
             adr_o      => adr_o,
             dat_i      => (others => '0'),
             dat_o      => dat_o,
             we_o       => we_o,
             sel_o      => sel_o,
             stb_o      => stb_o,
             ack_i      => '1',
             cyc_o      => cyc_o,

             clk        => clk,
             reset      => rst);

    uut : entity work.load_store_unit_to
    port map(uop_in     => uop_in,
             uop_out    => uop_out,
             cdb        => cdb,
             agu_port   => port_agu,
             bus_req    => bus_req,
             bus_resp   => bus_resp,
             bus_ready  => bus_ready,
             stall_in   => stall_in,
             stall_out  => stall_out,
             clk        => clk,
             reset      => rst);
end Behavioral;
