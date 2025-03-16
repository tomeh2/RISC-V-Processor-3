library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity simple_clock_divider is
    generic(
        DIVIDER_WIDTH: natural;
        INITIAL_OUTPUT_HIGH: boolean
    );
    port(
        clk_ref: in std_logic;
        clk_gen: out std_logic;
        reset: in std_logic;
        enable: in std_logic;

        divider: in std_logic_vector(DIVIDER_WIDTH - 1 downto 0)
    );
end simple_clock_divider;

architecture rtl of simple_clock_divider is
    signal R_counter: unsigned(DIVIDER_WIDTH - 1 downto 0);
    signal R_running: std_logic;
    signal R_output: std_logic;
begin
    process(clk_ref)
    begin
        if rising_edge(clk_ref) then
            if reset = '1' then
                R_running <= '0';
            else
                if R_running = '1' then
                    if enable = '0' then
                        R_running <= '0';                
                    end if;
    
                    if R_counter = 0 then
                        R_counter <= unsigned(divider);
                        R_output <= not R_output;
                    else
                        R_counter <= R_counter - 1;
                    end if;
                else
                    R_output <= '1' when INITIAL_OUTPUT_HIGH = true else '0';
                    if enable = '1' then
                        R_counter <= unsigned(divider);
                        R_running <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
    clk_gen <= R_output;
end rtl;
