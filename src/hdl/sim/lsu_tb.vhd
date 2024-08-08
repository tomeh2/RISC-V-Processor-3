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
    
    procedure F_gen_load_store(signal uop_in : inout T_uop; ls : std_logic; count : natural) is
    begin
        wait until rising_edge(clk);
        for i in 0 to count - 1 loop
            uop_in.op_type <= OPTYPE_LDST;
            uop_in.op_sel(0) <= ls;
            uop_in.valid <= '1';
            wait until rising_edge(clk);
        end loop;
        uop_in.op_type <= (others => '0');
        uop_in.op_sel(0) <= '0';
        uop_in.valid <= '0';
        wait until rising_edge(clk);
    end procedure;

    procedure F_gen_agu(signal port_agu : inout T_lsu_gen_port; ls : std_logic; base_addr : unsigned(ADDR_WIDTH - 1 downto 0); count : natural) is
    begin
        for i in 0 to count - 1 loop
            port_agu.address <= std_logic_vector(4 * i + base_addr);
            port_agu.data <= X"BABA_DADA";
            port_agu.address_valid <= '1';
            port_agu.data_valid <= ls;
            port_agu.rw <= ls;
            port_agu.sq_tag <= to_unsigned(i, SQ_TAG_WIDTH);
            port_agu.lq_tag <= to_unsigned(i, LQ_TAG_WIDTH);
            wait until rising_edge(clk);
        end loop;
        port_agu.address <= (others => '0');
        port_agu.data <= (others => '0');
        port_agu.address_valid <= '0';
        port_agu.data_valid <= '0';
        port_agu.rw <= '0';
        port_agu.sq_tag <= to_unsigned(0, SQ_TAG_WIDTH);
        port_agu.lq_tag <= to_unsigned(0, LQ_TAG_WIDTH);
        wait until rising_edge(clk);
    end procedure;
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
        uop_in <= UOP_ZERO;
        cdb <= UOP_ZERO;
        port_agu.address_valid <= '0';
        port_agu.data_valid <= '0';
        wait until falling_edge(clk);
        wait for CLK_PERIOD * 10;
        F_gen_load_store(uop_in, '1', 8);
        -- GENERATE LOADS
        F_gen_load_store(uop_in, '0', 8);
        wait for CLK_PERIOD * 10;
        wait until rising_edge(clk);
        -- GENERATE ADDR FOR LOADS
        F_gen_agu(port_agu, '0', X"0002_0000", 8);
        wait for CLK_PERIOD * 10;
        -- GENERATE ADDR & DATA FOR STORES
        F_gen_agu(port_agu, '1', X"0001_0000", 8);
        -- LSU SIM WITH BRANCH MISPREDICT
        wait for CLK_PERIOD * 100;
        F_gen_load_store(uop_in, '1', 4);
        -- GENERATE LOADS
        F_gen_load_store(uop_in, '0', 4);
        wait for CLK_PERIOD * 5;
        wait until rising_edge(clk);
        uop_in.valid <= '1';
        uop_in.branch_mask <= "0010";
        wait until rising_edge(clk);
        uop_in.valid <= '0';
        uop_in.branch_mask <= "0000";
        wait until rising_edge(clk);
        -- GENERATE STORES
        F_gen_load_store(uop_in, '1', 4);
        -- GENERATE LOADS
        F_gen_load_store(uop_in, '0', 4);
        wait until rising_edge(clk);
        F_gen_agu(port_agu, '1', X"0005_0000", 2);
        wait until rising_edge(clk);
        F_gen_agu(port_agu, '0', X"0006_0000", 2);
        wait until rising_edge(clk);
        cdb.valid <= '1';
        cdb.branch_mask <= "0010";
        cdb.branch_mispredicted <= '1';
        wait until rising_edge(clk);
        cdb.valid <= '0';
        cdb.branch_mask <= "0000";
        cdb.branch_mispredicted <= '0';
        wait;
    end process;

    bus_cntrl : entity work.wishbone_bus_controller
    port map(bus_req    => bus_req,
             bus_resp   => bus_resp,
             bus_ready   => bus_ready,
             adr_o      => adr_o,
             dat_i      => X"BABA_DEAD",
             dat_o      => dat_o,
             we_o       => we_o,
             sel_o      => sel_o,
             stb_o      => stb_o,
             ack_i      => '1',
             cyc_o      => cyc_o,

             clk        => clk,
             reset      => rst);

    uut : entity work.load_store_unit_to
    port map(uop_in         => uop_in,
             uop_out        => uop_out,
             cdb_in         => cdb,
             cdb_out        => open,
             cdb_request    => open,
             cdb_granted    => '1',
             agu_port       => port_agu,
             bus_req        => bus_req,
             bus_resp       => bus_resp,
             bus_ready      => bus_ready,
             stall_in       => stall_in,
             stall_out      => stall_out,
             clk            => clk,
             reset          => rst);
end Behavioral;
