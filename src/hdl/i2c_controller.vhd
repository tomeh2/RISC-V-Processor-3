library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2c_controller is
    generic(
        SLAVE_ADDRESS: std_logic_vector(6 downto 0);
        ENABLE_SIMULATION: boolean := false
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        wb_adr_i: in std_logic_vector(7 downto 0);
        wb_dat_o: out std_logic_vector(31 downto 0);
        wb_dat_i: in std_logic_vector(31 downto 0);
        wb_sel_i: in std_logic_vector(3 downto 0);
        wb_we_i: in std_logic;
        wb_cyc_i: in std_logic;
        wb_stb_i: in std_logic;
        wb_ack_o: out std_logic;

        i2c_sda: inout std_logic;
        i2c_scl: inout std_logic;

        sda_debug: out std_logic;
        scl_debug: out std_logic;

        sim_status_reg_tx_empty_bit: out std_logic;
        sim_status_reg_rx_full_bit: out std_logic;
        sim_control_reg_start_bit: out std_logic;
        sim_control_reg_restart_waiting_bit: out std_logic
    );
end i2c_controller;

architecture rtl of i2c_controller is
    signal timer_clkper_div_2: unsigned(15 downto 0);
    signal timer_clkper_div_4: unsigned(15 downto 0);
    signal timer_clkper_div_8: unsigned(15 downto 0);
    signal timer_clkper_div_16: unsigned(15 downto 0);

    type T_control_sm is (INACTIVE,
                            START,
                            XFER,
                            PREP_ACK,
                            PUT_ACK,
                            PUT_NACK,
                            GET_ACK,
                            RESTART_1,
                            RESTART_2,
                            STOP_1,
                            STOP_2);
    signal R_control_sm: T_control_sm;
    type T_mode is (MASTER, SLAVE);
    signal R_mode: T_mode;
    type T_phase is (ADDRESS, DATA);
    signal R_phase: T_phase;
    type T_xfer_direction is (READ, WRITE);
    signal R_xfer_direction: T_xfer_direction;

    -- Visible register addresses
    constant C_control_reg_addr: std_logic_vector(7 downto 0) := X"00";
    constant C_status_reg_addr: std_logic_vector(7 downto 0) := X"04";
    constant C_dev_address_reg_addr: std_logic_vector(7 downto 0) := X"08";
    constant C_tx_data_reg_addr: std_logic_vector(7 downto 0) := X"0C";
    constant C_rx_data_reg_addr: std_logic_vector(7 downto 0) := X"10";
    constant C_clkdiv_reg_addr: std_logic_vector(7 downto 0) := X"14";
    constant C_tx_num_bytes_reg_addr: std_logic_vector(7 downto 0) := X"18";

    -- Visible registers
    signal R_control: std_logic_vector(2 downto 0);
    signal R_status: std_logic_vector(1 downto 0);
    signal R_dev_address: std_logic_vector(7 downto 0);
    signal R_tx_data: std_logic_vector(7 downto 0);
    signal R_rx_data: std_logic_vector(7 downto 0);
    signal R_clkdiv: std_logic_vector(15 downto 0) := X"0010";
    signal R_num_bytes: std_logic_vector(7 downto 0);

    -- Internal registers
    signal R_tx_shift: std_logic_vector(7 downto 0);
    signal R_rx_shift: std_logic_vector(7 downto 0);
    signal R_rx_address: std_logic_vector(7 downto 0);
    signal R_i2c_sda, R_i2c_scl: std_logic;
    signal R_bytes_left: natural range 0 to 255;
    signal R_bits_left: natural range 0 to 7;
    signal R_wb_ack: std_logic := '0';

    -- Delay Timer Signals
    signal R_timer: unsigned(15 downto 0);
    signal R_timer_running: std_logic;
    signal R_timer_triggered: std_logic;
    signal timer_load_value: unsigned(15 downto 0);
    signal timer_start: std_logic;
    signal timer_reset: std_logic;
    signal timer_triggered: std_logic;

    signal ila_state: std_logic_vector(3 downto 0);
    signal ila_mode: std_logic;
    signal ila_phase: std_logic;
    signal ila_xfer_dir: std_logic;

    -- R_control register bits
    alias R_control_start_bit is R_control(0);
    alias R_control_restart_enable_bit is R_control(1);
    alias R_control_restart_waiting_bit is R_control(2);

    -- ======================
    -- R_STATUS REGISTER BITS
    -- ======================
    alias R_status_tx_data_reg_empty_bit is R_status(0);
    alias R_status_rx_data_reg_full_bit is R_status(1);

    -- Internal signals
    signal data_clock: std_logic;
    signal scd_clk_generated: std_logic;
    signal scd_enable: std_logic;
    signal i2c_sda_output: std_logic;
    signal i2c_sda_i, i2c_scl_i: std_logic;
    signal i2c_sda_i_filt: std_logic;
    signal i2c_sda_en, i2c_scl_en: std_logic;

    -- RE & FE detection
    signal R_i2c_sda_d, R_i2c_sda_2d: std_logic;
    signal R_data_clk_d, R_data_clk_2d: std_logic;
    signal R_i2c_sda_re, R_i2c_sda_fe: std_logic;
    signal R_data_clk_re, R_data_clk_fe: std_logic;

    signal i2c_sda_pre_filt, i2c_scl_pre_filt: std_logic;
    signal i2c_sda_post_filt, i2c_scl_post_filt: std_logic;
begin
    -- =====
    -- DEBUG
    -- =====
    sim_status_reg_tx_empty_bit <= R_status_tx_data_reg_empty_bit;
    sim_status_reg_rx_full_bit <= R_status_rx_data_reg_full_bit;
    sim_control_reg_restart_waiting_bit <= R_control_restart_waiting_bit;
    sim_control_reg_start_bit <= R_control_start_bit;
    
    sda_debug <= R_i2c_sda;
    scl_debug <= R_i2c_scl;

    -- Needed for simulation
    i2c_sda_pre_filt <= '1' when i2c_sda = 'Z' or i2c_sda = '1' else '0';
    i2c_scl_pre_filt <= '1' when i2c_scl = 'Z' or i2c_scl = '1' else '0';
    -- =====================
    -- INPUT DIGITAL FILTERS
    -- =====================
    -- SCL
    I_scl_in_dig_filt: entity work.digital_filter
    generic map(
        DEBOUNCER => false,
        DELAY_WIDTH_BITS => 8
    )
    port map(
        clk => clk,
        delay => X"0F",
        din => i2c_scl_pre_filt,
        dout => i2c_scl_post_filt
    );

    -- SDA
    I_sda_in_dig_filt: entity work.digital_filter
    generic map(
        DEBOUNCER => false,
        DELAY_WIDTH_BITS => 8
    )
    port map(
        clk => clk,
        delay => X"0F",
        din => i2c_sda_pre_filt,
        dout => i2c_sda_post_filt
    );
    
    -- ===========
    -- I2C CONTROL
    -- ===========
    
    process(clk)
    begin
        if rising_edge(clk) then
            R_i2c_sda <= i2c_sda_post_filt;
            R_i2c_scl <= i2c_scl_post_filt;
            R_i2c_sda_d <= i2c_sda_post_filt;
            R_i2c_sda_2d <= R_i2c_sda_d;

            R_data_clk_d <= data_clock;
            R_data_clk_2d <= R_data_clk_d;
        end if;
    end process;
    R_i2c_sda_re <= R_i2c_sda_d and not R_i2c_sda_2d;
    R_i2c_sda_fe <= not R_i2c_sda_d and R_i2c_sda_2d;
    R_data_clk_re <= R_data_clk_d and not R_data_clk_2d;
    R_data_clk_fe <= not R_data_clk_d and R_data_clk_2d;

    I_clkgen: entity work.simple_clock_divider
    generic map(
        DIVIDER_WIDTH => 16,
        INITIAL_OUTPUT_HIGH => true
    )
    port map(
        clk_ref => clk,
        clk_gen => scd_clk_generated,
        reset => reset,
        enable => scd_enable,
        divider => R_clkdiv
    );
    data_clock <= R_i2c_scl when R_mode = SLAVE else scd_clk_generated;

    -- Delay timer
    process(clk)
    begin
        if rising_edge(clk) then
            if timer_reset = '1' then
                R_timer <= (others => '0');
                R_timer_running <= '0';
                R_timer_triggered <= '0';
            else
                if R_timer_running = '1' then
                    if timer_reset = '1' then
                        R_timer_running <= '0';
                    elsif R_timer = 0 then
                        R_timer_running <= '0';
                        R_timer_triggered <= '1';
                    else
                        R_timer <= R_timer - 1;
                    end if;
                else
                    if timer_start = '1' then
                        R_timer <= timer_load_value;
                        R_timer_running <= '1';
                        R_timer_triggered <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    timer_triggered <= R_timer_triggered and not timer_reset and not timer_start;

    wb_ack_o <= R_wb_ack;
    timer_clkper_div_2 <= unsigned('0' & R_clkdiv(15 downto 1));
    timer_clkper_div_4 <= unsigned("00" & R_clkdiv(15 downto 2));
    timer_clkper_div_8 <= unsigned("000" & R_clkdiv(15 downto 3));
    timer_clkper_div_16 <= unsigned("0000" & R_clkdiv(15 downto 4));
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_control_sm <= INACTIVE;
                R_mode <= SLAVE;
                R_phase <= ADDRESS;
                R_xfer_direction <= READ;
                R_control <= "000";
                -- Make sure TX_DATA_REG_EMPTY bit is set
                R_status <= "01";
                R_wb_ack <= '0';
            else
                -- =============
                -- BUS INTERFACE
                -- =============
                wb_dat_o <= (others => '0');
                if wb_stb_i = '1' and wb_cyc_i = '1' then
                    case wb_adr_i is
                    when C_control_reg_addr =>
                        if wb_sel_i(0) = '1' and wb_we_i = '1' then
                            -- Only allow writing if START bit not already set (I2C is running)
                            if R_control_start_bit = '0' then
                                R_control_start_bit <= wb_dat_i(0);
                            end if;
                            R_control_restart_enable_bit <= wb_dat_i(1);

                            -- Allow clearing of the RESTART_WAITING bit if set (I2C waiting for RX/TX command)
                            if R_control_restart_waiting_bit = '1' then
                                R_control_restart_waiting_bit <= wb_dat_i(2);
                            end if;
                        end if;
                        wb_dat_o(2 downto 0) <= R_control;
                    when C_status_reg_addr =>
                        wb_dat_o(1 downto 0) <= R_status;
                    when C_dev_address_reg_addr =>
                        if wb_sel_i(0) = '1' and wb_we_i = '1' then
                            R_dev_address <= wb_dat_i(7 downto 0);
                        end if;
                        wb_dat_o(7 downto 0) <= R_dev_address;
                    when C_tx_data_reg_addr =>
                        if wb_sel_i(0) = '1' and wb_we_i = '1' then
                            R_tx_data <= wb_dat_i(7 downto 0);
                        end if;
                        wb_dat_o(7 downto 0) <= R_tx_data;
                        R_status_tx_data_reg_empty_bit <= '0';
                    when C_rx_data_reg_addr =>
                        wb_dat_o(7 downto 0) <= R_rx_data;
                        R_status_rx_data_reg_full_bit <= '0';
                    when C_clkdiv_reg_addr =>
                        if wb_sel_i(0) = '1' and wb_we_i = '1' then
                            R_clkdiv(7 downto 0) <= wb_dat_i(7 downto 0);
                        end if;

                        if wb_sel_i(1) = '1' and wb_we_i = '1' then
                            R_clkdiv(15 downto 8) <= wb_dat_i(15 downto 8);
                        end if;
                        wb_dat_o(15 downto 0) <= R_clkdiv;
                    when C_tx_num_bytes_reg_addr =>
                        if wb_sel_i(0) = '1' and wb_we_i = '1' then
                            R_num_bytes <= wb_dat_i(7 downto 0);
                        end if;
                        wb_dat_o(7 downto 0) <= R_num_bytes;
                    when others =>
                    end case;
                end if;
                R_wb_ack <= wb_stb_i and wb_cyc_i and not R_wb_ack;

                -- =====================
                -- CONTROL STATE MACHINE
                -- =====================
                timer_reset <= '0';
                timer_start <= '0';
                timer_load_value <= timer_clkper_div_2;
                case R_control_sm is
                when INACTIVE =>
                    -- Timer Control
                    timer_reset <= '1';

                    -- START condition detected on the bus, enter slave mode read address
                    if R_i2c_sda_fe = '1' and R_i2c_scl = '1' then
                        R_mode <= SLAVE;
                        R_control_sm <= START;
                    -- Bit 0 in the control register is set, enter master mode
                    elsif R_control_start_bit = '1' then
                        R_mode <= MASTER;
                        R_control_sm <= START;
                    end if;
                when START =>
                    if R_mode = MASTER then
                        if R_data_clk_fe = '1' then
                            R_control_sm <= XFER;
                            R_phase <= ADDRESS;
                            R_xfer_direction <= WRITE;
                            R_tx_shift <= R_dev_address;
                            R_bytes_left <= to_integer(unsigned(R_num_bytes));
                            R_bits_left <= 7;
                            timer_reset <= '1';
                            R_status_tx_data_reg_empty_bit <= '1';
                        end if;
                    else
                        if R_data_clk_fe = '1' then
                            R_control_sm <= XFER;
                            R_phase <= ADDRESS;
                            R_xfer_direction <= READ;
                            R_bits_left <= 7;
                        end if;
                    end if;
                when XFER =>
                    -- STOP CONDITION
                    if R_i2c_scl = '1' and R_i2c_sda_re = '1' and R_mode = SLAVE then
                        R_control_sm <= INACTIVE;
                        R_control_start_bit <= '0';
                    end if;

                    case R_xfer_direction is
                    when READ =>
                        if R_data_clk_re = '1' then
                            R_rx_shift(0) <= R_i2c_sda;
                            R_rx_shift(7 downto 1) <= R_rx_shift(6 downto 0);
                        end if;
                    when WRITE =>
                        if R_data_clk_fe = '1' and R_bits_left /= 0 then
                            R_tx_shift(7 downto 1) <= R_tx_shift(6 downto 0);
                            R_tx_shift(0) <= '0';
                        end if;
                    when others =>
                    end case;

                    if R_data_clk_fe = '1' then
                        if R_bits_left = 0 then
                            R_control_sm <= PREP_ACK;
                        else
                            R_bits_left <= R_bits_left - 1;
                        end if;
                    end if;
                when PREP_ACK =>
                    -- Controller in MASTER mode
                    if R_mode = MASTER then
                        R_phase <= DATA;

                        if R_phase = DATA then
                            R_bytes_left <= R_bytes_left - 1;
                        end if;

                        if R_xfer_direction = READ then
                            -- If no more bytes are left to be read then put NACK
                            -- on the I2C_SDA line to signal end to READ, otherwise
                            -- just ACK (Value of 1 indicates that last byte was read)
                            if R_bytes_left = 1 then
                                R_control_sm <= PUT_NACK;
                            else
                                R_control_sm <= PUT_ACK;
                            end if;

                            if R_phase = DATA then
                                R_rx_data <= R_rx_shift;
                                R_status_rx_data_reg_full_bit <= '1';
                            end if; 
                        elsif R_xfer_direction = WRITE then
                            R_control_sm <= GET_ACK;
                            R_tx_shift <= R_tx_data;
                            R_status_tx_data_reg_empty_bit <= '1';

                            -- If we just finished sending the address then check
                            -- (by reading bit 0 in the address reg) whether we
                            -- need to perform READs from the device or WRITEs
                            if R_phase = ADDRESS then
                                if R_dev_address(0) = '1' then
                                    R_xfer_direction <= READ;
                                else
                                    R_xfer_direction <= WRITE;
                                end if;
                            end if;
                        end if;
                    -- Controller in SLAVE mode
                    else
                        if R_xfer_direction = READ then
                            if R_phase = ADDRESS then
                                R_phase <= DATA;
                                if R_rx_shift(7 downto 1) = SLAVE_ADDRESS then
                                    R_control_sm <= PUT_ACK;
                                    if R_rx_shift(0) = '1' then
                                        R_xfer_direction <= WRITE;
                                    else
                                        R_xfer_direction <= READ;
                                    end if;
                                else
                                    R_control_sm <= PUT_NACK;
                                end if;
                            else
                                R_control_sm <= PUT_ACK;
                                R_rx_data <= R_rx_shift;
                                R_status_rx_data_reg_full_bit <= '1';
                            end if;
                        elsif R_xfer_direction = WRITE then
                            R_control_sm <= GET_ACK;
                        end if;
                    end if;
                when PUT_ACK =>
                    if R_data_clk_fe = '1' then
                        if R_mode = MASTER then
                            if R_bytes_left = 0 then
                                if R_control_restart_enable_bit = '1' then
                                        R_control_sm <= RESTART_1;
                                else
                                        R_control_sm <= STOP_1;
                                end if;
                                R_control_sm <= STOP_1;
                            else
                                -- If we are driving ACK on the bus as a master then
                                -- the controller is performing a READ from the SLAVE
                                -- I2C device
                                R_control_sm <= XFER;
                                R_bits_left <= 7;
                            end if;
                        else
                            R_control_sm <= XFER;
                            R_bits_left <= 7;
                        end if;
                    end if;
                when PUT_NACK =>
                    if R_data_clk_fe = '1' then
                        if R_mode = MASTER then
                            R_control_sm <= STOP_1;
                        else
                            
                        end if;
                    end if;
                when GET_ACK =>
                    if R_data_clk_fe = '1' then
                        if R_mode = MASTER then
                            -- NACK
                            if R_i2c_sda = '1' then
                                R_control_sm <= STOP_1;
                            -- ACK
                            else
                                if R_bytes_left = 0 then
                                    if R_control_restart_enable_bit = '1' then
                                        R_control_sm <= RESTART_1;
                                    else
                                        R_control_sm <= STOP_1;
                                    end if;
                                else
                                    R_control_sm <= XFER;
                                    R_bits_left <= 7;
                                end if;
                            end if;
                        else
                            -- Receiving the ACK signal means that the slave
                            -- is read from, and master generates ACK. Therefore
                            -- we want to either stop sending if the master sends
                            -- NACK, or continue otherwise.
                            -- NACK
                            if R_i2c_sda = '1' then
                                R_control_sm <= INACTIVE;
                                R_control_start_bit <= '0';
                            -- ACK
                            else
                                R_control_sm <= XFER;
                                R_bits_left <= 7;
                            end if;
                        end if;
                    end if;
                when RESTART_1 =>
                    if R_data_clk_re = '1' then
                        R_control_sm <= RESTART_2;
                        R_control_restart_waiting_bit <= '1';
                        timer_start <= '1';
                        timer_load_value <= timer_clkper_div_2;
                    end if;
                when RESTART_2 =>
                    if R_control_restart_waiting_bit = '0' and timer_triggered = '1' then
                        R_control_sm <= START;
                        timer_reset <= '1';
                    end if;
                when STOP_1 =>
                    if R_data_clk_re = '1' then
                        timer_start <= '1';
                        R_control_sm <= STOP_2;
                    end if;
                when STOP_2 =>
                    if timer_triggered = '1' then
                        R_control_sm <= INACTIVE;
                        R_control_start_bit <= '0';
                        timer_reset <= '1';
                    end if;
                when others =>
                    
                end case;
            end if;
        end if;
    end process;
    i2c_sda_output <= R_tx_shift(7);

    process(R_control_sm, R_mode, i2c_sda_output, data_clock, timer_triggered,
        R_xfer_direction)
    begin
        i2c_scl_en <= '0';
        i2c_sda_en <= '0';

        i2c_scl_i <= data_clock;
        i2c_sda_i <= i2c_sda_output;

        scd_enable <= '0';
        case R_control_sm is
        when INACTIVE =>
        when START =>
            if R_mode = MASTER then
                scd_enable <= '1';
                i2c_sda_i <= '0';
                i2c_scl_en <= '1';
                i2c_sda_en <= '1';
            else
            
            end if;
        when XFER =>
            scd_enable <= '1';
            if R_mode = MASTER then
                i2c_scl_en <= '1';
            end if;

            if R_xfer_direction = WRITE then
                i2c_sda_en <= '1';
            end if;
        when PREP_ACK =>
            scd_enable <= '1';
            if R_mode = MASTER then
                i2c_scl_en <= '1';
            end if;
        when PUT_ACK =>
            scd_enable <= '1';
            if R_mode = MASTER then
                i2c_scl_en <= '1';
            end if;
            i2c_sda_en <= '1';
            i2c_sda_i <= '0';
        when PUT_NACK =>
            scd_enable <= '1';
            if R_mode = MASTER then
                i2c_scl_en <= '1';
            end if;
            i2c_sda_en <= '1';
            i2c_sda_i <= '1';
        when GET_ACK =>
            scd_enable <= '1';
            if R_mode = MASTER then
                i2c_scl_en <= '1';
            end if;
        when RESTART_1 =>
            scd_enable <= '1';
            i2c_scl_en <= '1';
            i2c_sda_en <= '1';

            i2c_sda_i <= '1';
        when RESTART_2 =>
            
        when STOP_1 =>
            i2c_sda_en <= '1';
            i2c_scl_en <= '1';
            scd_enable <= '1';
        when STOP_2 =>
            i2c_scl_en <= '0';

            if timer_triggered = '1' then
                i2c_sda_en <= '0';
            else
                i2c_sda_en <= '1';
            end if;
        when others =>
        end case;
    end process;

    -- Output SDA filter & delay
    I_sda_i_dig_filt: entity work.digital_filter
    generic map(
        DEBOUNCER => false,
        DELAY_WIDTH_BITS => 16
    )
    port map(
        clk => clk,
        delay => std_logic_vector(timer_clkper_div_16),
        din => i2c_sda_i,
        dout => i2c_sda_i_filt
    );

    -- I2C devices are only allowed to pull the corresponding line LOW
    -- which enables connecting multiple devices to the bus while ensuring
    -- that we can't create a situation where one device is driving HIGH
    -- and another LOW at the same time. HIGH state is established through
    -- a pull-up resistor on the bus.
    i2c_scl <= '0' when i2c_scl_en = '1' and i2c_scl_i = '0' else 'Z';
    i2c_sda <= '0' when i2c_sda_en = '1' and i2c_sda_i_filt = '0' else 'Z';

--    your_instance_name : entity work.ila_0
--PORT MAP (
--	clk => clk,



--	probe0 => R_control,
--	probe1 => R_status,
--	probe2 => R_dev_address,
--	probe3 => ila_state,
--    probe4(0) => ila_mode,
--    probe5(0) => R_i2c_scl,
--    probe6(0) => R_i2c_sda,
--    probe7(0) => ila_xfer_dir,
--    probe8(0) => ila_phase
--);

    with R_control_sm select ila_state <=
        "0000" when INACTIVE,
        "0001" when START,
        "0010" when XFER,
        "0011" when PREP_ACK,
        "0100" when GET_ACK,
        "0101" when PUT_ACK,
        "0110" when PUT_NACK,
        "0111" when STOP_1,
        "1000" when STOP_2,
        "1001" when RESTART_1,
        "1010" when RESTART_2;

    with R_mode select ila_mode <=
        '0' when SLAVE,
        '1' when MASTER;

    with R_xfer_direction select ila_xfer_dir <=
        '0' when READ,
        '1' when WRITE;
    
    with R_phase select ila_phase <=
        '0' when ADDRESS,
        '1' when DATA;
end rtl;
