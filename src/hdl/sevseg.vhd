library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sevseg is
    port(
        clk: in std_logic;
        reset: in std_logic;
        
        wb_adr_i: in std_logic_vector(3 downto 2);
        wb_dat_o: out std_logic_vector(31 downto 0);
        wb_dat_i: in std_logic_vector(31 downto 0);
        wb_sel_i: in std_logic_vector(3 downto 0);
        wb_we_i: in std_logic;
        wb_cyc_i: in std_logic;
        wb_stb_i: in std_logic;
        wb_ack_o: out std_logic;

        cathodes: out std_logic_vector(7 downto 0);
        -- Capable of driving 8 common anode 7-segment displays
        anodes: out std_logic_vector(7 downto 0)
    );
end sevseg;

architecture rtl of sevseg is
    type T_cathode_regfile is array (7 downto 0) of std_logic_vector(7 downto 0);
    signal R_cathode_regfile: T_cathode_regfile;

    signal R_cathode_reg_output_sel: unsigned(2 downto 0) := "000";
    signal R_refresh_counter: unsigned(23 downto 0) := X"000000";
    signal R_refresh_counter_loadval: unsigned(23 downto 0) := X"0000FF";
    signal R_anode_enable_circ_reg: std_logic_vector(7 downto 0) := X"80";
begin
    P_bus_control: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_refresh_counter_loadval <= X"0000FF";
            else
                if wb_stb_i = '1' then
                    case wb_adr_i is
                    when "00" =>
                        wb_dat_o <= R_cathode_regfile(3) &
                                    R_cathode_regfile(2) &
                                    R_cathode_regfile(1) &
                                    R_cathode_regfile(0);
                    when "01" =>
                        wb_dat_o <= R_cathode_regfile(7) &
                                    R_cathode_regfile(6) &
                                    R_cathode_regfile(5) &
                                    R_cathode_regfile(4);
                    when "10" =>
                        wb_dat_o <= X"0000" &
                          std_logic_vector(R_refresh_counter_loadval(23 downto 8));
                    when others =>

                    end case;
                    if wb_we_i = '1' and wb_ack_o = '1' then
                        case wb_adr_i is
                        when "00" =>
                            if wb_sel_i(0) = '1' then
                                R_cathode_regfile(4) <= wb_dat_i(7 downto 0);
                            end if;
        
                            if wb_sel_i(1) = '1' then
                                R_cathode_regfile(5) <= wb_dat_i(15 downto 8);
                            end if;
        
                            if wb_sel_i(2) = '1' then
                                R_cathode_regfile(6) <= wb_dat_i(23 downto 16);
                            end if;
        
                            if wb_sel_i(3) = '1' then
                                R_cathode_regfile(7) <= wb_dat_i(31 downto 24);
                            end if;
                        when "01" =>
                            if wb_sel_i(0) = '1' then
                                R_cathode_regfile(0) <= wb_dat_i(7 downto 0);
                            end if;
        
                            if wb_sel_i(1) = '1' then
                                R_cathode_regfile(1) <= wb_dat_i(15 downto 8);
                            end if;
        
                            if wb_sel_i(2) = '1' then
                                R_cathode_regfile(2) <= wb_dat_i(23 downto 16);
                            end if;
        
                            if wb_sel_i(3) = '1' then
                                R_cathode_regfile(3) <= wb_dat_i(31 downto 24);
                            end if;
                        when "10" =>
                            if wb_sel_i(0) = '1' then
                                R_refresh_counter_loadval(15 downto 8)
                                  <= unsigned(wb_dat_i(7 downto 0));
                            end if;

                            if wb_sel_i(1) = '1' then
                                R_refresh_counter_loadval(23 downto 16)
                                  <= unsigned(wb_dat_i(15 downto 8));
                            end if;
                        when others =>

                        end case;
                    end if;
                end if;
            end if;
        end if;
    end process;
    wb_ack_o <= wb_stb_i and not wb_ack_o when rising_edge(clk);

    P_sevseg_cntrl: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_anode_enable_circ_reg <= X"80";
                R_refresh_counter <= X"000000";
                R_cathode_reg_output_sel <= "000";
            else
                if R_refresh_counter = 0 then
                    R_refresh_counter <= R_refresh_counter_loadval;
                    R_cathode_reg_output_sel <= R_cathode_reg_output_sel + 1;

                    R_anode_enable_circ_reg(6 downto 0) <= R_anode_enable_circ_reg(7 downto 1);
                    R_anode_enable_circ_reg(7) <= R_anode_enable_circ_reg(0);
                else
                    R_refresh_counter <= R_refresh_counter - 1;
                end if;
            end if;
        end if;
    end process;
    cathodes <= not R_cathode_regfile(to_integer(R_cathode_reg_output_sel));
    anodes <= not R_anode_enable_circ_reg;
end rtl;
