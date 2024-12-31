library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;
use WORK.ROM_INIT.ALL;

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
    constant C_ROM_ADDR_BITS: natural := F_min_bits(C_size_kb * 1024);
    constant M_rom: T_rom := C_rom_init;
    signal wb_addr_internal: natural;
begin
    wb_addr_internal <= to_integer(unsigned(wb_addr(C_ROM_ADDR_BITS - 1 downto 2)));
    P_rom_cntrl: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wb_ack <= '0';
            else
                wb_ack <= '0';
                if wb_stb = '1' and wb_ack = '0' then
                    wb_rdata <= M_rom(wb_addr_internal);
                    wb_ack <= '1';
                end if;
            end if;
        end if;
    end process;

end rtl;
