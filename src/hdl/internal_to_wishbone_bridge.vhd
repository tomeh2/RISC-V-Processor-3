library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity internal_to_wishbone_bridge is
    port(
        clk: in std_logic;
        reset: in std_logic;

        internal_bus_req: in T_bus_request;
        internal_bus_resp: out T_bus_response;
        wishbone_bus_req: out T_wishbone_req;
        wishbone_bus_resp: in T_wishbone_resp
    );
end internal_to_wishbone_bridge;

architecture rtl of internal_to_wishbone_bridge is
    signal R_req_address: std_logic_vector(31 downto 0);
    signal R_req_wdata: std_logic_vector(31 downto 0);
    signal R_req_bsel: std_logic_vector(3 downto 0);
    signal R_req_we: std_logic;
    signal R_cancelled: std_logic;
    signal R_resp_rdata: std_logic_vector(31 downto 0);
    type T_state is (IDLE, BUSY, RESPONSE);
    signal R_state: T_state;
    
    signal wdata_temp: std_logic_vector(31 downto 0);
    signal bsel_temp: std_logic_vector(3 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_state <= IDLE;
            else
                case R_state is
                when IDLE =>
                    if internal_bus_req.valid = '1' and internal_bus_resp.ready = '1' then
                        R_state <= BUSY;
                        R_req_address <= internal_bus_req.address;
                        R_req_wdata <= wdata_temp;
                        R_req_bsel <= bsel_temp;
                        R_req_we <= internal_bus_req.rw;
                    end if;
                when BUSY =>
                    if internal_bus_req.cancel = '1' then
                        R_cancelled <= '1';
                    end if;
                
                    if wishbone_bus_resp.ack = '1' then
                        if R_cancelled = '1' or R_req_we = '1' or internal_bus_req.cancel = '1' then
                            R_state <= IDLE;
                            R_cancelled <= '0';
                        else
                            R_resp_rdata <= wishbone_bus_resp.dat;
                            R_state <= RESPONSE;
                        end if;
                    end if;
                when RESPONSE =>
                    if (internal_bus_req.ready = '1' and internal_bus_resp.valid = '1') or internal_bus_req.cancel = '1' then
                        R_state <= IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;

    process(R_state, R_req_address, R_req_wdata, R_req_bsel, R_req_we, R_resp_rdata, internal_bus_req.cancel)
    begin
        wishbone_bus_req.stb <= '0';
        wishbone_bus_req.cyc <= '0';

        internal_bus_resp.ready <= '0';
        internal_bus_resp.valid <= '0';

        wishbone_bus_req.adr <= R_req_address;
        wishbone_bus_req.dat <= R_req_wdata;
        wishbone_bus_req.sel <= R_req_bsel;
        wishbone_bus_req.we <= R_req_we;

        internal_bus_resp.address <= R_req_address;
        internal_bus_resp.data <= R_resp_rdata;
        internal_bus_resp.rw <= R_req_we;

        case R_state is
        when IDLE =>
            internal_bus_resp.ready <= '1';
        when BUSY =>
            wishbone_bus_req.stb <= '1';
            wishbone_bus_req.cyc <= '1';
        when RESPONSE =>
            internal_bus_resp.valid <= not internal_bus_req.cancel;
        end case;
    end process;

    P_wb_req_dat_o_gen : process(internal_bus_req)
    begin
        wdata_temp <= (others => '0');
        bsel_temp <= (others => '0');
        case internal_bus_req.data_size is
        when "00" =>
            case internal_bus_req.address(1 downto 0) is
            when "00" =>
                wdata_temp(7 downto 0) <= internal_bus_req.data(7 downto 0);
                bsel_temp <= "0001";
            when "01" =>
                wdata_temp(15 downto 8) <= internal_bus_req.data(7 downto 0);
                bsel_temp <= "0010";
            when "10" =>
                wdata_temp(23 downto 16) <= internal_bus_req.data(7 downto 0);
                bsel_temp <= "0100";
            when "11" =>
                wdata_temp(31 downto 24) <= internal_bus_req.data(7 downto 0);
                bsel_temp <= "1000";
            when others =>
            end case;
        when "01" =>
            case internal_bus_req.address(1) is
            when '0' =>
                wdata_temp(15 downto 0) <= internal_bus_req.data(15 downto 0);
                bsel_temp <= "0011";
            when '1' =>
                wdata_temp(31 downto 16) <= internal_bus_req.data(15 downto 0);
                bsel_temp <= "1100";
            when others =>
            end case;
        when "10" =>
            wdata_temp(31 downto 0) <= internal_bus_req.data(31 downto 0);
            bsel_temp <= "1111";
        when others =>
        end case; 
    end process;
end rtl;
