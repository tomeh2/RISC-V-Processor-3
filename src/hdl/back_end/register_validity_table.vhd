library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_validity_table is
    port(
        clk : in std_logic;
        reset : in std_logic;
    
        read_addr_1 : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        read_addr_2 : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        read_out_1 : out std_logic;
        read_out_2 : out std_logic;

        set_addr : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        set_en : in std_logic;
        unset_addr : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        unset_en : in std_logic
    );
end register_validity_table;

architecture rtl of register_validity_table is
    signal R_reg_valid_bits : std_logic_vector(PHYS_REGFILE_ENTRIES - 1 downto 0);
begin
    P_valid_bits_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_reg_valid_bits <= (others => '1');
            else
                if set_en = '1' then
                    R_reg_valid_bits(F_vec_to_int(set_addr)) <= '1';
                end if;
                
                if unset_en = '1' then
                    if unsigned(unset_addr) /= 0 then
                        R_reg_valid_bits(F_vec_to_int(unset_addr)) <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    read_out_1 <= R_reg_valid_bits(F_vec_to_int(read_addr_1));
    read_out_2 <= R_reg_valid_bits(F_vec_to_int(read_addr_2));
end rtl;
