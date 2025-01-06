library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity branch_target_buffer is
    generic(
        ADDR_WIDTH: natural;
        ENTRIES: natural            -- MUST BE A POWER OF 2
    );
    port(
        clk: in std_logic;
        -- Branch for which we are predicting
        branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        branch_target_prediction: out unsigned(ADDR_WIDTH - 1 downto 0);
        -- Branch which has just been executed and has a known outcome
        executed_branch_pc: in unsigned(ADDR_WIDTH - 1 downto 0);
        executed_branch_target: in unsigned(ADDR_WIDTH - 1 downto 0);
        executed_branch_update_en: in std_logic
    );
end branch_target_buffer;

architecture rtl of branch_target_buffer is
    constant C_btb_index_size: natural := integer(ceil(log2(real(ENTRIES))));

    signal btb_index_write: unsigned(C_btb_index_size - 1 downto 0);
    signal btb_index_read: unsigned(C_btb_index_size - 1 downto 0);
    type T_btb is array (0 to ENTRIES - 1) of unsigned(ADDR_WIDTH - 1 downto 0);
    signal M_btb: T_btb := (others => (others => '0'));
begin
    btb_index_write <= executed_branch_pc(C_btb_index_size + 1 downto 2);
    btb_index_read <= branch_pc(C_btb_index_size + 1 downto 2);
    -- UPDATE LOGIC
    process(clk)
    begin
        if rising_edge(clk) then
            if executed_branch_update_en = '1' then
                M_btb(to_integer(btb_index_write)) <= executed_branch_target;
            end if;
        end if;
    end process;

    -- READ LOGIC
    process(branch_pc, btb_index_read)
    begin
        branch_target_prediction <= M_btb(to_integer(btb_index_read));
    end process;

end rtl;
