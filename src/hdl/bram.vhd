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

use WORK.CPU_PKG.ALL;

entity bram is
    generic(
        USE_BYTE_ENABLE: boolean;
        WORD_LENGTH: natural;
        NUM_WORDS: natural
    );
    port(
        clk: in std_logic;
        reset: in std_logic;

        addr_write: in std_logic_vector(F_min_bits(NUM_WORDS) - 1 downto 0);
        write_enable: in std_logic;
        byte_enable: in std_logic_vector(integer(ceil(real(WORD_LENGTH) / 8.0)) - 1 downto 0) := (others => '0');
        data_write: in std_logic_vector(WORD_LENGTH - 1 downto 0);
        addr_read: in std_logic_vector(F_min_bits(NUM_WORDS) - 1 downto 0);
        data_read: out std_logic_vector(WORD_LENGTH - 1 downto 0)
    );
end bram;

architecture rtl of bram is
    type T_bram is array (0 to NUM_WORDS - 1) of std_logic_vector(WORD_LENGTH - 1 downto 0);
    signal M_bram: T_bram;

    signal addr_write_int: natural;
    signal addr_read_int: natural;
begin
    addr_write_int <= to_integer(unsigned(addr_write));
    addr_read_int <= to_integer(unsigned(addr_read));

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
            
            else
                if write_enable = '1' then
                    if USE_BYTE_ENABLE = true then
                        for i in 0 to integer(ceil(real(WORD_LENGTH) / 8.0)) - 1 loop
                            if byte_enable(i) = '1' then
                                M_bram(addr_write_int)(8 * (i + 1) - 1 downto 8 * i) <= data_write(8 * (i + 1) - 1 downto 8 * i);
                            end if;
                        end loop;
                    else
                        M_bram(addr_write_int) <= data_write;
                    end if;
                end if;
                for i in 0 to WORD_LENGTH - 1 loop
                    data_read(i) <= '0' when M_bram(addr_read_int)(i) = 'U' else M_bram(addr_read_int)(i);
                end loop;
            end if;
        end if;
    end process;
end rtl;