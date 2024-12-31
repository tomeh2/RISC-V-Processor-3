library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity gpio is
    port(
        clk: in std_logic;
        reset: in std_logic;

        wb_adr_i: in std_logic_vector(2 downto 2);
        wb_dat_o: out std_logic_vector(31 downto 0);
        wb_dat_i: in std_logic_vector(31 downto 0);
        wb_sel_i: in std_logic_vector(3 downto 0);
        wb_we_i: in std_logic;
        wb_cyc_i: in std_logic;
        wb_stb_i: in std_logic;
        wb_ack_o: out std_logic;

        gpin: in std_logic_vector(31 downto 0);
        gpout: out std_logic_vector(31 downto 0)
    );
end gpio;

architecture rtl of gpio is
    signal R_gpin: std_logic_vector(31 downto 0);
    signal R_gpout: std_logic_vector(31 downto 0);
    signal R_ack: std_logic;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_gpin <= (others => '0');
                R_gpout <= (others => '0');
            else
                R_gpin <= gpin;
                if wb_stb_i = '1' then
                    if wb_we_i = '1' and R_ack = '1' then
                        if wb_adr_i(2) = '1' then
                            if wb_sel_i(0) = '1' then
                                R_gpout(7 downto 0) <= wb_dat_i(7 downto 0);
                            end if;

                            if wb_sel_i(1) = '1' then
                                R_gpout(15 downto 8) <= wb_dat_i(15 downto 8);
                            end if;

                            if wb_sel_i(2) = '1' then
                                R_gpout(23 downto 16) <= wb_dat_i(23 downto 16);
                            end if;

                            if wb_sel_i(3) = '1' then
                                R_gpout(31 downto 24) <= wb_dat_i(31 downto 24);
                            end if;
                        end if;
                    end if;

                    if wb_adr_i(2) = '1' then
                        wb_dat_o <= R_gpout;
                    else
                        wb_dat_o <= R_gpin;
                    end if;
                end if;
            end if;
        end if;
    end process;
    R_ack <= wb_stb_i and not R_ack when rising_edge(clk);
    wb_ack_o <= R_ack;

    gpout <= R_gpout;
end rtl;
