library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity address_generation_unit is
    port(
        uop_in  : in T_uop;

        agu_out : out T_lsu_agu_port;

        clk         : in std_logic;
        reset       : in std_logic
    );
end address_generation_unit;

architecture rtl of address_generation_unit is
    signal gen_address : std_logic_vector(31 downto 0);
begin
    gen_address <= std_logic_vector(unsigned(uop_in.reg_read_1_data) + unsigned(uop_in.immediate));
    agu_out.address_valid <= '1' when uop_in.valid = '1' else '0';
    agu_out.data <= uop_in.reg_read_2_data;
    agu_out.data_valid <= '1' when uop_in.valid = '1' and uop_in.funct(3) = '1' else '0';
    agu_out.sq_tag <= uop_in.sq_index;
    agu_out.lq_tag <= uop_in.lq_index;
    agu_out.rw <= uop_in.funct(3);

    -- Data mask generation
    process(uop_in.funct(1 downto 0), gen_address)
    begin
        agu_out.data_mask <= "0000";
        case uop_in.funct(1 downto 0) is
        when "00" =>            -- Byte
            case gen_address(1 downto 0) is
            when "00" =>
                agu_out.data_mask <= "0001";
            when "01" =>
                agu_out.data_mask <= "0010";
            when "10" =>
                agu_out.data_mask <= "0100";
            when "11" =>
                agu_out.data_mask <= "1000";
            when others =>
            
            end case;
        when "01" =>            -- Half-Word
            case gen_address(1 downto 0) is
            when "00" =>
                agu_out.data_mask <= "0011";
            when "10" =>
                agu_out.data_mask <= "1100";
            when others =>
            
            end case;
        when "10" =>            -- Word
            agu_out.data_mask <= "1111";
        when others =>
        
        end case;
    end process;
    agu_out.address <= gen_address(31 downto 2);
end rtl;
