library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity fifo is
    generic(
        BITS_PER_ENTRY : natural;
        ENTRIES : natural
    );
    port(
        clk : in std_logic;
        reset : in std_logic;

        data_in : in std_logic_vector(BITS_PER_ENTRY - 1 downto 0);
        data_out : out std_logic_vector(BITS_PER_ENTRY - 1 downto 0);
        
        get_en : in std_logic;
        put_en : in std_logic;
        
        full : out std_logic;
        empty : out std_logic
    );
end fifo;

architecture rtl of fifo is
    type T_fifo is array (0 to ENTRIES - 1) of std_logic_vector(BITS_PER_ENTRY - 1 downto 0);
    signal M_fifo : T_fifo;

    signal R_head : unsigned(integer(ceil(log2(real(ENTRIES)))) - 1 downto 0);
    signal R_head_next : unsigned(integer(ceil(log2(real(ENTRIES)))) - 1 downto 0);
    signal R_tail : unsigned(integer(ceil(log2(real(ENTRIES)))) - 1 downto 0);
    signal R_tail_next : unsigned(integer(ceil(log2(real(ENTRIES)))) - 1 downto 0);
    signal R_util : unsigned(integer(ceil(log2(real(ENTRIES)))) downto 0);
    
    signal i_full : std_logic;
    signal i_empty : std_logic;
    
    signal R_data_out : std_logic_vector(BITS_PER_ENTRY - 1 downto 0);
begin
    P_next_gen : process(R_head, R_tail)
    begin
        if R_head = ENTRIES - 1 then
            R_head_next <= (others => '0');
        else
            R_head_next <= R_head + 1;
        end if;
        
        if R_tail = ENTRIES - 1 then
            R_tail_next <= (others => '0');
        else
            R_tail_next <= R_tail + 1;
        end if;
    end process;

    P_fifo_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_head <= (others => '0');
                R_tail <= (others => '0');
                R_util <= (others => '0');
            else
                R_data_out <= M_fifo(to_integer(R_head));
                
                if put_en = '1' and i_full = '0' then
                    R_tail <= R_tail_next;
                    R_util <= R_util + 1;
                    M_fifo(to_integer(R_tail)) <= data_in;
                    
                    if i_empty = '1' then
                        R_data_out <= data_in;
                    end if;
                end if;
                
                if get_en = '1' and i_empty = '0' then
                    R_head <= R_head_next;
                    R_util <= R_util - 1;
                    
                    R_data_out <= M_fifo(to_integer(R_head_next));
                end if;

                if put_en = '1' and i_full = '0' and get_en = '1' and i_empty = '0' then
                    R_util <= R_util;
                end if;
            end if;
        end if;
    end process;
    data_out <= R_data_out;
    
    i_full <= '1' when R_util = ENTRIES else '0';
    i_empty <= '1' when R_util = 0 else '0';
    
    full <= i_full;
    empty <= i_empty;
end rtl;
