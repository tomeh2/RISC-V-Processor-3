library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_16550 is
    port(
        clk: in std_logic;
        reset: in std_logic;
        
        wb_adr_i: in std_logic_vector(2 downto 2);
        wb_dat_o: out std_logic_vector(31 downto 0);
        wb_dat_i: in std_logic_vector(31 downto 0);
        wb_sel_i: in std_logic_vector(3 downto 0);
        wb_we_i: in std_logic;
        wb_cyc_i: in std_logic;
        wb_stb_i: in std_logic;
        wb_ack_o: out std_logic;

        tx: out std_logic;
        rx: in std_logic
    );
end uart_16550;

architecture rtl of uart_16550 is
    signal wb_ack : std_logic := '0';
    --
    signal tx_fifo_put_en: std_logic;
    signal tx_fifo_get_en: std_logic;
    signal tx_fifo_full: std_logic;
    signal tx_fifo_empty: std_logic;
    signal tx_fifo_next_word: std_logic_vector(7 downto 0);

    signal rx_fifo_put_en: std_logic;
    signal rx_fifo_get_en: std_logic;
    signal rx_fifo_empty: std_logic;
    signal rx_fifo_full: std_logic;
    signal rx_fifo_data_out: std_logic_vector(7 downto 0);
    -- REGISTERS
    -- 0x0 Read DLAB = 0
    signal R_receiver_buffer: std_logic_vector(7 downto 0);
    -- 0x0 Write DLAB = 0
    signal R_transmitter_holding: std_logic_vector(7 downto 0);
    -- 0x0 DLAB = 1
    signal R_divisor_latch_l: std_logic_vector(7 downto 0);
    -- 0x1 DLAB = 0
    signal R_interrupt_enable: std_logic_vector(7 downto 0);
    -- 0x1 DLAB = 1
    signal R_divisor_latch_m: std_logic_vector(7 downto 0);
    -- 0x2 Read
    signal R_interrupt_ident: std_logic_vector(7 downto 0);
    -- 0x2 Write
    signal R_fifo_cntrl: std_logic_vector(7 downto 0);
    -- 0x3
    signal R_line_cntrl: std_logic_vector(7 downto 0);
    -- 0x4
    signal R_modem_cntrl: std_logic_vector(7 downto 0);
    -- 0x5
    signal R_line_status: std_logic_vector(7 downto 0);
    -- 0x6
    signal R_modem_status: std_logic_vector(7 downto 0);
    -- 0x7
    signal R_scratch : std_logic_vector(7 downto 0);
    -- TX CONTROL
    type T_tx_state is (IDLE, START_BIT, DATA, STOP_BIT);
    signal R_tx_state: T_tx_state;
    signal baud_div: unsigned(15 downto 0);
    signal R_tx_baud_div_cnt: unsigned(15 downto 0);
    signal R_tx_clk_div_16_cnt: unsigned(3 downto 0);
    signal R_tx_active: std_logic;
    signal R_tx_bits_left: unsigned(3 downto 0);
    signal R_tx_shift_reg: std_logic_vector(7 downto 0);

    -- RX CONTROL
    type T_rx_state is (IDLE, START_BIT, DATA, STOP_BIT);
    signal R_rx_state: T_rx_state;
    signal R_rx_baud_div_cnt: unsigned(15 downto 0);
    signal R_rx_clk_div_16_cnt: unsigned(3 downto 0);
    signal R_rx_bits_left: unsigned(3 downto 0);
    signal R_rx_shift_reg: std_logic_vector(9 downto 0);
begin
    tx_fifo_put_en <= '1' when wb_stb_i = '1' and
                               wb_ack = '1' and
                               wb_adr_i(2) = '0' and
                               wb_we_i = '1' and
                               R_line_cntrl(7) = '0' and
                               wb_sel_i = "0001" else '0';
    tx_fifo_get_en <= '1' when R_tx_state = IDLE and
                               tx_fifo_empty = '0' else '0';
    I_tx_fifo: entity work.fifo
    generic map(BITS_PER_ENTRY => 8,
                OUTPUT_REG_ENABLE => true,
                ENTRIES => 16)
    port map(clk => clk,
             reset => reset,
             data_in => wb_dat_i(7 downto 0),
             data_out => tx_fifo_next_word,
             get_en => tx_fifo_get_en,
             put_en => tx_fifo_put_en,
             full => tx_fifo_full,
             empty => tx_fifo_empty);

    I_rx_fifo: entity work.fifo
    generic map(BITS_PER_ENTRY => 8,
                OUTPUT_REG_ENABLE => true,
                ENTRIES => 16)
    port map(clk => clk,
             reset => reset,
             data_in => R_rx_shift_reg(9 downto 2),
             data_out => rx_fifo_data_out,
             get_en => rx_fifo_get_en,
             put_en => rx_fifo_put_en,
             full => rx_fifo_full,
             empty => rx_fifo_empty);
    rx_fifo_put_en <= '1' when R_rx_state = STOP_BIT and
                               R_rx_clk_div_16_cnt = 7 and
                               R_rx_baud_div_cnt = 0 else '0';
    rx_fifo_get_en <= '1' when wb_stb_i = '1' and
                               wb_ack = '1' and
                               wb_we_i = '0' and
                               wb_adr_i(2) = '0' and
                               wb_sel_i = "0001" and
                               R_line_cntrl(7) = '0' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_receiver_buffer <= "00000000";
                R_transmitter_holding <= "00000000";
                R_interrupt_enable <= "00000000";
                R_interrupt_ident <= "00000001";
                R_fifo_cntrl <= "00000000";
                R_line_cntrl <= "00000000";
                R_modem_cntrl <= "00000000";
                R_line_status <= "01100000";
                R_modem_status <= "00000000";
                R_divisor_latch_l <= "00000000";
                R_divisor_latch_m <= "00000000";
            else
                if wb_stb_i = '1' and wb_ack = '1' then
                    if wb_we_i = '1' then
                        if wb_adr_i(2) = '0' then
                            case wb_sel_i is
                            when "0001" =>
                                if R_line_cntrl(7) = '1' then
                                    R_divisor_latch_l <= wb_dat_i(7 downto 0);
                                end if;
                            when "0010" =>
                                if R_line_cntrl(7) = '1' then
                                    R_divisor_latch_m <= wb_dat_i(15 downto 8);
                                end if;
                            when "0100" =>
                            when "1000" =>
                                R_line_cntrl <= wb_dat_i(31 downto 24);
                            when others =>
                            end case;
                        end if;
                    end if;
                end if;

                if wb_stb_i = '1' and wb_we_i = '0' then
                    if wb_adr_i(2) = '1' then
                        wb_dat_o(7 downto 0) <= R_modem_cntrl;
                        wb_dat_o(15 downto 8) <= R_line_status;
                        wb_dat_o(23 downto 16) <= R_modem_status;
                        wb_dat_o(31 downto 24) <= R_scratch;
                    else
                        if R_line_cntrl(7) = '1' then
                            wb_dat_o(7 downto 0) <= R_divisor_latch_l;
                            wb_dat_o(15 downto 8) <= R_divisor_latch_m;
                        else
                            wb_dat_o(7 downto 0) <= rx_fifo_data_out;
                            wb_dat_o(15 downto 8) <= R_interrupt_enable;
                        end if;
                        wb_dat_o(23 downto 16) <= R_interrupt_ident;
                        wb_dat_o(31 downto 24) <= R_line_cntrl;
                    end if;
                end if;
                R_line_status(0) <= not rx_fifo_empty;
                R_line_status(5) <= tx_fifo_empty;
            end if;
        end if;
    end process;

    baud_div <= unsigned(R_divisor_latch_m) &
                unsigned(R_divisor_latch_l);
    -- ==========
    -- TX CONTROL
    -- ==========
    P_tx_cntrl: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_tx_bits_left <= (others => '0');
                R_tx_shift_reg <= (others => '0');
                R_tx_active <= '0';
            else
                case R_tx_state is
                when IDLE =>
                    if tx_fifo_empty = '0' then
                        R_tx_state <= START_BIT;
                        R_tx_shift_reg(7 downto 0) <= tx_fifo_next_word;
                    end if;
                when START_BIT =>
                    if R_tx_clk_div_16_cnt = 0 and R_tx_baud_div_cnt = 0 then
                        R_tx_state <= DATA;
                        R_tx_bits_left <= to_unsigned(7, 4);
                    end if;
                when DATA =>
                    if R_tx_clk_div_16_cnt = 0 and R_tx_baud_div_cnt = 0 then
                        R_tx_shift_reg(6 downto 0) <= R_tx_shift_reg(7 downto 1);
                        R_tx_shift_reg(7) <= '0';
                        R_tx_bits_left <= R_tx_bits_left - 1;
                        if R_tx_bits_left = 0 then
                            R_tx_state <= STOP_BIT;
                        end if;
                    end if;
                when STOP_BIT =>
                    if R_tx_clk_div_16_cnt = 0 and R_tx_baud_div_cnt = 0 then
                        R_tx_state <= IDLE;
                    end if;
                when others =>

                end case;
            end if;
        end if;
    end process;

    P_tx_baud_gen: process(clk)
    begin
        if rising_edge(clk) then
            case R_tx_state is
            when IDLE =>
                R_tx_baud_div_cnt <= baud_div;
                R_tx_clk_div_16_cnt <= to_unsigned(15, 4);
            when others =>
                if R_tx_baud_div_cnt = 0 then
                    R_tx_baud_div_cnt <= baud_div;
                    R_tx_clk_div_16_cnt <= R_tx_clk_div_16_cnt - 1;
                else
                    R_tx_baud_div_cnt <= R_tx_baud_div_cnt - 1;
                end if;
            end case;
        end if;
    end process;

    tx <= '0' when R_tx_state = START_BIT else
          R_tx_shift_reg(0) when R_tx_state = DATA else
          '1' when R_tx_state = STOP_BIT else
          '1';
    -- ==========
    -- RX CONTROL
    -- ==========
    P_rx_cntrl: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_rx_state <= IDLE;
            else
                case R_rx_state is
                when IDLE =>
                    if rx = '0' then
                        R_rx_state <= START_BIT;
                        R_rx_bits_left <= (others => '0');
                        R_rx_shift_reg <= (others => '0');
                    end if;
                when START_BIT =>
                    if R_rx_clk_div_16_cnt = 7 and R_rx_baud_div_cnt = 0 then
                        if rx = '0' then
                            R_rx_state <= DATA;
                            R_rx_bits_left <= to_unsigned(7, 4);
                        else
                            R_rx_state <= IDLE;
                        end if;
                    end if;
                when DATA =>
                    if R_rx_clk_div_16_cnt = 7 and R_rx_baud_div_cnt = 0 then
                        -- Shift new bit from RX into RX register
                        R_rx_shift_reg(9) <= rx;
                        R_rx_shift_reg(8 downto 0) <= R_rx_shift_reg(9 downto 1);

                        R_rx_bits_left <= R_rx_bits_left - 1;
                        if R_rx_bits_left = 0 then
                            R_rx_state <= STOP_BIT;
                        end if;
                    end if;
                when STOP_BIT =>
                    if R_rx_clk_div_16_cnt = 7 and R_rx_baud_div_cnt = 0 then
                        R_rx_state <= IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;

    P_rx_baud_gen: process(clk)
    begin
        if rising_edge(clk) then
            case R_rx_state is
            when IDLE =>
                R_rx_baud_div_cnt <= baud_div;
                R_rx_clk_div_16_cnt <= to_unsigned(15, 4);
            when others =>
                if R_rx_baud_div_cnt = 0 then
                    R_rx_baud_div_cnt <= baud_div;
                    R_rx_clk_div_16_cnt <= R_rx_clk_div_16_cnt - 1;
                else
                    R_rx_baud_div_cnt <= R_rx_baud_div_cnt - 1;
                end if;
            end case;
        end if;
    end process;

    wb_ack <= wb_cyc_i and not wb_ack when rising_edge(clk);
    wb_ack_o <= wb_ack;
end rtl;
