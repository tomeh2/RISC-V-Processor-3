library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

use WORK.CPU_PKG.ALL;

-- N-bit saturating counters
entity branch_predictor_satcnt is
    generic(
        ADDR_WIDTH: natural;
        BITS_PER_COUNTER: natural;
        ENTRIES: natural                -- MUST BE POWER OF 2
    );
    port(
        clk: in std_logic;
        branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        branch_taken_prediction: out std_logic;
        executed_branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        executed_branch_taken: in std_logic;
        executed_branch_update_en: in std_logic
    );
end branch_predictor_satcnt;

architecture rtl of branch_predictor_satcnt is
    constant C_bp_index_size: natural := integer(ceil(log2(real(ENTRIES))));
    constant C_counter_min: unsigned(BITS_PER_COUNTER - 1 downto 0) := (others => '0');
    constant C_counter_max: unsigned(BITS_PER_COUNTER - 1 downto 0) := (others => '1');

    signal bp_index_write: unsigned(C_bp_index_size - 1 downto 0);
    signal bp_index_read: unsigned(C_bp_index_size - 1 downto 0);
    type T_saturating_counters is array (0 to ENTRIES - 1) of unsigned(BITS_PER_COUNTER - 1 downto 0);
    signal R_saturating_counters: T_saturating_counters := (others => (others => '0'));
begin
    bp_index_write <= executed_branch_pc(C_bp_index_size + 1 downto 2);
    bp_index_read <= branch_pc(C_bp_index_size + 1 downto 2);
    -- COUNTER UPDATE LOGIC
    process(clk)
    begin
        if rising_edge(clk) then
            if executed_branch_update_en = '1' then
                if executed_branch_taken = '1' then
                    if R_saturating_counters(to_integer(bp_index_write)) /= C_counter_max then
                        R_saturating_counters(to_integer(bp_index_write)) <= R_saturating_counters(to_integer(bp_index_write)) + 1;
                    end if;
                else
                    if R_saturating_counters(to_integer(bp_index_write)) /= C_counter_min then
                        R_saturating_counters(to_integer(bp_index_write)) <= R_saturating_counters(to_integer(bp_index_write)) - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Predict branch taken if MSB of the corresponding counter is 1
    branch_taken_prediction <= R_saturating_counters(to_integer(bp_index_read))(BITS_PER_COUNTER - 1);
end rtl;
