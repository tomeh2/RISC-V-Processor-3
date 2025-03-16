library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity i2c_tb is

end i2c_tb;

architecture rtl of i2c_tb is
    constant CLK_PERIOD : time := 10ns;
    constant RST_DURATION : time := CLK_PERIOD * 10;
    constant I2C_CLK_PERIOD: time := 1us;
    
    signal clk, rst: std_logic;
    signal i2c_sda, i2c_scl: std_logic;

    signal wb_adr_i: std_logic_vector(31 downto 0);
    signal wb_dat_o: std_logic_vector(31 downto 0);
    signal wb_dat_i: std_logic_vector(31 downto 0);
    signal wb_sel_i: std_logic_vector(3 downto 0);
    signal wb_we_i: std_logic;
    signal wb_cyc_i: std_logic;
    signal wb_stb_i: std_logic;
    signal wb_ack_o: std_logic;

    signal i2c1_tx_data_empty: std_logic;
    signal i2c1_rx_data_ready: std_logic;
    signal i2c1_restart_waiting: std_logic;
    signal i2c1_start: std_logic;

    signal i2c2_tx_data_empty: std_logic;
    signal i2c2_rx_data_ready: std_logic;
    signal i2c2_restart_waiting: std_logic;
    signal i2c2_start: std_logic;

    procedure F_i2c_write(constant addr: std_logic_vector(6 downto 0);
                          constant data: std_logic_vector(7 downto 0);
                          signal i2c_sda: inout std_logic;
                          signal i2c_scl: inout std_logic) is
    begin 
        -- START CONDITION
        i2c_sda <= '0';
        wait for I2C_CLK_PERIOD;
        i2c_scl <= '0';
        wait for I2C_CLK_PERIOD;

        for i in 6 downto 0 loop
            i2c_scl <= '0';
            i2c_sda <= addr(i);
            wait for I2C_CLK_PERIOD / 2;
            i2c_scl <= '1';
            wait for I2C_CLK_PERIOD / 2;
        end loop;
        i2c_sda <= '0';
        i2c_scl <= '0';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '1';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= 'Z';
        i2c_scl <= '0';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '1';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '0';
        wait for I2C_CLK_PERIOD * 10;
        
        for i in 7 downto 0 loop
            i2c_scl <= '0';
            i2c_sda <= data(i);
            wait for I2C_CLK_PERIOD / 2;
            i2c_scl <= '1';
            wait for I2C_CLK_PERIOD / 2;
        end loop;
        i2c_sda <= 'Z';
        i2c_scl <= '0';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '1';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '0';
        i2c_sda <= '0';
        wait for I2C_CLK_PERIOD / 2;
        i2c_scl <= '1';
        wait for I2C_CLK_PERIOD / 2;
        i2c_sda <= '1';
        wait for 100ns;
    end procedure;
begin
    process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    process
        procedure F_wb_write(constant data: std_logic_vector(31 downto 0);
            constant address: std_logic_vector(31 downto 0);
            constant sel: std_logic_vector(3 downto 0)) is
        begin
            wb_dat_i <= data;
            wb_adr_i <= address;
            wb_sel_i <= sel;
            wb_we_i <= '1';
            wb_stb_i <= '1';
            wb_cyc_i <= '1';
            wait until wb_ack_o = '1' and rising_edge(clk);
            wb_dat_i <= (others => '0');
            wb_adr_i <= (others => '0');
            wb_sel_i <= (others => '0');
            wb_we_i <= '0';
            wb_stb_i <= '0';
            wb_cyc_i <= '0';
        end procedure;

        procedure F_wb_read(constant address: std_logic_vector(31 downto 0);
            constant sel: std_logic_vector(3 downto 0);
            signal data: out std_logic_vector(31 downto 0)) is
        begin
            wb_adr_i <= address;
            wb_sel_i <= sel;
            wb_we_i <= '0';
            wb_stb_i <= '1';
            wb_cyc_i <= '1';
            wait until wb_ack_o = '1' and falling_edge(clk);
            data <= wb_dat_o;
            wait until wb_ack_o = '1' and rising_edge(clk);
            wb_adr_i <= (others => '0');
            wb_sel_i <= (others => '0');
            wb_we_i <= '0';
            wb_stb_i <= '0';
            wb_cyc_i <= '0';
        end procedure;
    begin
        wb_adr_i <= (others => '0');
        wb_sel_i <= (others => '0');
        wb_we_i <= '0';
        wb_stb_i <= '0';
        wb_cyc_i <= '0';
        i2c_sda <= 'Z';
        i2c_scl <= 'Z';
        rst <= '1';
        wait for 100ns;
        rst <= '0';
        wait for 1us;
        -- SET DIVIDER
        F_wb_write(X"00_00_00_7F", X"0000_0014", "1111");
        -- SET TX ADDR REG (ADDRESS 0x08, WRITE)
        F_wb_write(X"00_00_00_10", X"0000_0008", "1111");
        -- SET TX DATA REG
        F_wb_write(X"00_00_00_C8", X"0000_000C", "1111");
        -- SET NUM BYTES
        F_wb_write(X"00_00_00_02", X"0000_0018", "1111");
        -- START MASTER WRITE
        F_wb_write(X"00_00_00_01", X"0000_0000", "1111");
        wait until i2c1_tx_data_empty = '1';
        -- SET TX DATA (DATA)
        F_wb_write(X"00_00_00_AB", X"0000_000C", "1111");
        wait until i2c1_tx_data_empty = '1';
        -- SET TX DATA (DATA)
        F_wb_write(X"00_00_00_3C", X"0000_000C", "1111");
        wait until i2c1_start = '0';
        wait for 50us;
        -- SET TX ADDR REG (ADDRESS 0x08, READ)
        F_wb_write(X"00_00_00_11", X"0000_0008", "1111");
        -- SET NUM BYTES
        F_wb_write(X"00_00_00_01", X"0000_0018", "1111");
        -- START MASTER READ
        F_wb_write(X"00_00_00_01", X"0000_0000", "1111");
        wait until i2c1_rx_data_ready = '1';
        wait until i2c1_start = '0';
        wait for 50us;
        -- SET TX ADDR REG (ADDRESS 0x08, WRITE)
        F_wb_write(X"00_00_00_10", X"0000_0008", "1111");
        -- SET TX DATA (DATA)
        F_wb_write(X"00_00_00_7A", X"0000_000C", "1111");
        -- SET NUM BYTES
        F_wb_write(X"00_00_00_01", X"0000_0018", "1111");
        -- ENABLE REPEATED START
        F_wb_write(X"00_00_00_02", X"0000_0000", "1111");
        -- START MASTER WRITE
        F_wb_write(X"00_00_00_03", X"0000_0000", "1111");
        wait until i2c1_restart_waiting = '1';
        wait for 1us;
        -- SET TX ADDR REG (ADDRESS 0x08, READ)
        F_wb_write(X"00_00_00_11", X"0000_0008", "1111");
        -- SET NUM BYTES
        F_wb_write(X"00_00_00_01", X"0000_0018", "1111");
        -- DISABLE REPEATED START
        F_wb_write(X"00_00_00_01", X"0000_0000", "1111");
        wait;
    end process;
    uut1: entity work.i2c_controller
    generic map(
        SLAVE_ADDRESS => "0010011"
    )
    port map(
        clk => clk,
        reset => rst,
        wb_adr_i(7 downto 0) => wb_adr_i(7 downto 0),
        wb_dat_o => wb_dat_o,
        wb_dat_i => wb_dat_i,
        wb_sel_i => wb_sel_i,
        wb_we_i => wb_we_i,
        wb_cyc_i => wb_cyc_i,
        wb_stb_i => wb_stb_i,
        wb_ack_o => wb_ack_o,
        i2c_sda => i2c_sda,
        i2c_scl => i2c_scl,
        sim_status_reg_tx_empty_bit => i2c1_tx_data_empty,
        sim_status_reg_rx_full_bit => i2c1_rx_data_ready,
        sim_control_reg_restart_waiting_bit => i2c1_restart_waiting,
        sim_control_reg_start_bit => i2c1_start
    );
    
    uut2: entity work.i2c_controller
    generic map(
        SLAVE_ADDRESS => "0001000"
    )
    port map(
        clk => clk,
        reset => rst,
        wb_adr_i => (others => '0'),
        wb_dat_o => open,
        wb_dat_i => (others => '0'),
        wb_sel_i => (others => '0'),
        wb_we_i => '0',
        wb_cyc_i => '0',
        wb_stb_i => '0',
        wb_ack_o => open,
        i2c_sda => i2c_sda,
        i2c_scl => i2c_scl,
        sim_status_reg_tx_empty_bit => i2c2_tx_data_empty,
        sim_status_reg_rx_full_bit => i2c2_rx_data_ready,
        sim_control_reg_restart_waiting_bit => i2c2_restart_waiting,
        sim_control_reg_start_bit => i2c2_start
    );
end rtl;
