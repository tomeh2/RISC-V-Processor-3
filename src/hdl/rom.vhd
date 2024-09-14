library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;
use WORK.ELF_PKG.ALL;

use STD.TEXTIO.ALL;

entity rom is
    generic(
        C_size_kb : natural := 1
    );
    port(
        clk : in std_logic;
        reset : in std_logic;
        
        wb_addr : in std_logic_vector(31 downto 0);
        wb_rdata : out std_logic_vector(31 downto 0);
        wb_cyc : in std_logic;
        wb_stb : in std_logic;
        wb_ack : out std_logic
    );
end rom;

architecture rtl of rom is
    type T_rom is array (0 to 1023) of std_logic_vector(31 downto 0);
    signal M_rom : T_rom;
    
    impure function F_read_elf_file return T_rom is
        variable elf_struct : T_elf_file;
        variable mem : T_byte_array(0 to 2047);
        variable rom : T_rom;
    begin
        F_read_elf("C:/Projects/test.elf", elf_struct);
        F_print_elf_struct(elf_struct);
        F_construct_memory_image(elf_struct, mem);
        
        for i in 0 to mem'length / 4 - 1 loop
            rom(i)(7 downto 0) := mem(i * 4);
            rom(i)(15 downto 8) := mem(i * 4 + 1);
            rom(i)(23 downto 16) := mem(i * 4 + 2);
            rom(i)(31 downto 24) := mem(i * 4 + 3);
        end loop;
        return rom;
    end function;
    
    constant C_ROM_ADDR_BITS : natural := F_min_bits(C_size_kb * 1024 / 4);
begin
    P_rom_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wb_ack <= '0';
                M_rom <= F_read_elf_file;
            else
                wb_ack <= '0';
                if wb_stb = '1' then
                    wb_rdata <= M_rom(F_vec_to_int(wb_addr(C_ROM_ADDR_BITS + 1 downto 2)));
                    wb_ack <= '1';
                end if;
            end if;
        end if;
    end process;

end rtl;
