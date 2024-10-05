--===============================================================================
--MIT License

--Copyright (c) 2024 Tomislav Harmina

--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:

--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.

--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.
--===============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.MATH_REAL.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ram is
    generic(
        SIZE_KB : integer
    );
    port(
        -- ========== BUS SIGNALS ==========
        wb_addr : in std_logic_vector(integer(ceil(log2(real(SIZE_KB * 1024)))) - 1 downto 2);
        wb_wdata : in std_logic_vector(31 downto 0);
        wb_rdata : out std_logic_vector(31 downto 0);
        wb_stb : in std_logic;
        wb_cyc : in std_logic;
        wb_sel : in std_logic_vector(3 downto 0);
        wb_we : in std_logic;
        wb_ack : out std_logic;
        -- =================================
        
        -- ========== CONTROL SIGNALS ==========
        clk : in std_logic;
        reset : in std_logic
        -- =====================================
    );
end ram;

architecture rtl of ram is
    constant NB_COL : integer := 4;
    constant COL_WIDTH : integer := 8;
    constant BUS_ADDR_BITS : integer := integer(ceil(log2(real(SIZE_KB * 1024))));

    type ram_type is array (0 to SIZE_KB * 256 - 1) of std_logic_vector(NB_COL * COL_WIDTH - 1 downto 0);
    signal ram : ram_type;
    
    signal wb_ack_i : std_logic;
begin
    ram_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if wb_stb = '1' then
                wb_rdata <= ram(to_integer(unsigned(wb_addr(BUS_ADDR_BITS - 1 downto 2))));

                for i in 0 to NB_COL - 1 loop
                    if wb_sel(i) = '1' and wb_we = '1' then
                        ram(to_integer(unsigned(wb_addr(BUS_ADDR_BITS - 1 downto 2))))((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH) <= wb_wdata((i + 1) * COL_WIDTH - 1 downto i * COL_WIDTH);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    wb_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wb_ack_i <= '0';
            else
                wb_ack_i <= wb_stb;
            end if;
        end if;
    end process;
    wb_ack <= wb_ack_i;
end rtl;