library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity digital_filter is
    generic(
        -- Setting DEBOUNCER to true will implement the digital filter as a debouncer.
        -- A debouncer will wait for the signal to be STABLE for at least the amount
        -- of time specified by delay. If set to false it will just wait for the speicfied
        -- amount of time before propagating the input signal, regardless of any signal
        -- changes in the meantime (use as glitch filter and delay insertion).
        DEBOUNCER: boolean;
        DELAY_WIDTH_BITS: natural
    );
    port(
        clk: in std_logic;

        -- How much time has to pass since input signal changed for it to
        -- also change at the output. Changes that last less then the set
        -- delay will not show up at the output at all.
        delay: in std_logic_vector(DELAY_WIDTH_BITS - 1 downto 0);

        din: in std_logic;
        dout: out std_logic
    );
end digital_filter;

architecture rtl of digital_filter is
    signal din_changed: std_logic;
    signal R_din_d: std_logic := '0';
    signal R_out: std_logic := '0';
    signal R_counter: unsigned(DELAY_WIDTH_BITS - 1 downto 0);

    type T_state is (IDLE, ACTIVE);
    signal R_state: T_state := IDLE;
begin
    din_changed <= R_din_d xor din;
    process(clk)
    begin
        if rising_edge(clk) then
            R_din_d <= din;

            case R_state is
            when IDLE =>
                if din_changed = '1' then
                    R_state <= ACTIVE;
                    R_counter <= unsigned(delay);
                end if;
            when ACTIVE =>
                -- Propagate input signal after timeout
                if R_counter = 0 then
                    R_state <= IDLE;
                    R_out <= din;
                else
                    if DEBOUNCER = true then
                        -- Reload counter if any changes in din were detected
                        -- (ensure stability for at least delay amount of time)
                        if din_changed = '1' then
                            R_counter <= unsigned(delay);
                        else
                            R_counter <= R_counter - 1;
                        end if;
                    else
                        R_counter <= R_counter - 1;
                    end if;
                end if;
            end case;
        end if;
    end process;
    dout <= R_out;
end rtl;
