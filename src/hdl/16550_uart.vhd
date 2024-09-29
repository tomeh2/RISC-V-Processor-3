library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_16550 is
    port(
        clk : in std_logic;
        reset : in std_logic;
        
        wb_adr_i : in std_logic_vector(31 downto 2);
        wb_dat_o : out std_logic_vector(31 downto 0);
        wb_dat_i : in std_logic_vector(31 downto 0);
        wb_sel_i : in std_logic_vector(3 downto 0);
        wb_cyc_i : in std_logic;
        wb_stb_i : in std_logic;
        wb_ack_o : out std_logic;

        tx : out std_logic;
        rx : in std_logic
    );
end uart_16550;

architecture rtl of uart_16550 is
    signal wb_ack : std_logic := '0';
    --
    signal tx_fifo_put_en : std_logic;
    signal tx_fifo_get_en : std_logic;
    signal tx_fifo_full : std_logic;
    signal tx_fifo_empty : std_logic;
    signal tx_fifo_next_word : std_logic_vector(7 downto 0);
    -- REGISTERS
    -- 0x0 Read DLAB = 0
    signal R_receiver_buffer : std_logic_vector(7 downto 0);
    -- 0x0 Write DLAB = 0
    signal R_transmitter_holding : std_logic_vector(7 downto 0);
    -- 0x0 DLAB = 1
    signal R_divisor_latch_l : std_logic_vector(7 downto 0);
    -- 0x1 DLAB = 0
    signal R_interrupt_enable : std_logic_vector(7 downto 0);
    -- 0x1 DLAB = 1
    signal R_divisor_latch_m : std_logic_vector(7 downto 0);
    -- 0x2 Read
    signal R_interrupt_ident : std_logic_vector(7 downto 0);
    -- 0x2 Write
    signal R_fifo_cntrl : std_logic_vector(7 downto 0);
    -- 0x3
    signal R_line_cntrl : std_logic_vector(7 downto 0);
    -- 0x4
    signal R_modem_cntrl : std_logic_vector(7 downto 0);
    -- 0x5
    signal R_line_status : std_logic_vector(7 downto 0);
    -- 0x6
    signal R_modem_status : std_logic_vector(7 downto 0);
    -- 0x7
    signal R_scratch : std_logic_vector(7 downto 0);
    -- TX CONTROL
    signal baud_div : unsigned(15 downto 0);
    signal R_baud_div_cnt : unsigned(15 downto 0);
    signal baud_div_en : std_logic;
    signal R_clk_div_16_cnt : unsigned(3 downto 0);
    signal clk_div_16_en : std_logic;
    signal txc_start_tx : std_logic;
    signal R_txc_tx_active : std_logic;
    signal R_txc_bits_left : unsigned(3 downto 0);
    signal R_txc_shift_reg : std_logic_vector(11 downto 0);
begin
    tx_fifo_get_en <= txc_start_tx;
    I_tx_fifo : entity work.fifo
    generic map(BITS_PER_ENTRY => 8,
                ENTRIES => 16)
    port map(clk => clk,
             reset => reset,
             data_in => wb_dat_i(7 downto 0),
             data_out => tx_fifo_next_word,
             get_en => tx_fifo_get_en,
             put_en => tx_fifo_put_en,
             full => tx_fifo_full,
             empty => tx_fifo_empty);

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
                    if wb_adr_i(2) = '0' then
                        case wb_sel_i is
                        when "0001" =>
                            if R_line_cntrl(7) = '1' then
                                R_divisor_latch_l <= wb_dat_i(7 downto 0);
                            end if;
                        when "001-" =>
                            if R_line_cntrl(7) = '1' then
                                R_divisor_latch_m <= wb_dat_i(7 downto 0);
                            end if;
                        when "01--" =>
                        when "1---" =>
                            R_line_cntrl <= wb_dat_i(7 downto 0);
                        when others =>
                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
    tx_fifo_put_en <= '1' when wb_stb_i = '1' and
                               wb_ack = '1' and
                               wb_adr_i(2) = '0' and
                               R_line_cntrl(7) = '0' and
                               wb_sel_i = "0001" else '0';

    -- ==========
    -- TX CONTROL
    -- ==========
    baud_div <= unsigned(R_divisor_latch_m) &
                unsigned(R_divisor_latch_l);
    txc_start_tx <= not tx_fifo_empty and not R_txc_tx_active;
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_txc_bits_left <= (others => '0');
                R_txc_shift_reg <= (others => '0');
                R_txc_tx_active <= '0';
            else
                if R_txc_tx_active = '0' then
                    if txc_start_tx = '1' then
                        R_txc_tx_active <= '1';
                        R_txc_bits_left <= to_unsigned(9, 4);
                        R_txc_shift_reg <= '0' &
                                           tx_fifo_next_word &
                                           '1' & "00";
                    end if;
                else
                    if baud_div_en = '1' then
                        if R_txc_bits_left = 0 then
                            R_txc_tx_active <= '0';
                        else
                            R_txc_bits_left <= R_txc_bits_left - 1;
                            R_txc_shift_reg(11 downto 1) <= R_txc_shift_reg(10 downto 0);
                            R_txc_shift_reg(0) <= '0';
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    P_baud_gen : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_clk_div_16_cnt <= (others => '0');
                R_baud_div_cnt <= (others => '0');
            else
                if R_txc_tx_active = '1' then
                    R_clk_div_16_cnt <= R_clk_div_16_cnt + 1;
                else
                    R_clk_div_16_cnt <= (others => '0');
                end if;
                
                if R_txc_tx_active = '1' then
                    if baud_div_en = '1' then
                        R_baud_div_cnt <= (others => '0');
                    elsif clk_div_16_en = '1' then
                        R_baud_div_cnt <= R_baud_div_cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    clk_div_16_en <= '1' when R_clk_div_16_cnt = 15 else '0';
    baud_div_en <= '1' when R_baud_div_cnt = baud_div else '0';

    tx <= R_txc_shift_reg(11) when R_txc_tx_active = '1' else '1';

    wb_ack <= wb_cyc_i and not wb_ack when rising_edge(clk);
    wb_ack_o <= wb_ack;
end rtl;
