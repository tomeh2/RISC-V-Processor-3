library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

entity wishbone_bus_controller is
    generic(
        NUM_MASTERS : natural
    );
    port(
        -- CPU SIDE BUS
        bus_req : in T_bus_request_array(0 to NUM_MASTERS - 1);
        bus_resp : out T_bus_response_array(0 to NUM_MASTERS - 1);

        wb_req : out T_wishbone_req;
        wb_resp : in T_wishbone_resp;

        clk : in std_logic;
        reset : in std_logic
    );
end wishbone_bus_controller;

architecture rtl of wishbone_bus_controller is
    type T_wb_state is (IDLE, READ_LOCK, WRITE_LOCK);
    signal R_wb_state : T_wb_state;
    signal R_lock_bus_id : natural range 0 to NUM_MASTERS - 1;
    
    signal R_active_bus_reqests : T_bus_request_array(0 to NUM_MASTERS - 1);

    signal wb_resp_dat_i : std_logic_vector(31 downto 0);
    signal wb_req_dat_o : std_logic_vector(31 downto 0);
    signal wb_req_sel_o : std_logic_vector(3 downto 0);
begin
    P_active_req_regs : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to NUM_MASTERS - 1 loop
                    R_active_bus_reqests(i).valid <= '0';
                end loop;
            else
                for i in 0 to NUM_MASTERS - 1 loop
                    if R_active_bus_reqests(i).valid = '0' and bus_req(i).valid = '1' then
                        R_active_bus_reqests(i) <= bus_req(i);
                    end if;
                end loop;

                if wb_resp.ack = '1' and R_wb_state /= IDLE then
                    R_active_bus_reqests(R_lock_bus_id).valid <= '0';
                end if;
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_wb_state <= IDLE;
            else
                case R_wb_state is
                when IDLE =>
                    for i in 0 to NUM_MASTERS - 1 loop
                        if R_active_bus_reqests(i).valid = '1' then
                            R_lock_bus_id <= i;
                            if R_active_bus_reqests(i).rw = '0' then
                                R_wb_state <= READ_LOCK;
                            else
                                R_wb_state <= WRITE_LOCK;
                            end if;
                        end if;
                    end loop;
                when READ_LOCK =>
                    if wb_resp.ack = '1' then
                        R_wb_state <= IDLE;
                    end if;
                when WRITE_LOCK =>
                    if wb_resp.ack = '1' then
                        R_wb_state <= IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;

    process(R_active_bus_reqests, R_lock_bus_id, R_wb_state, wb_resp.ack, wb_req_sel_o, wb_req_dat_o, wb_resp_dat_i)
    begin
        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).ready <= not R_active_bus_reqests(i).valid;
        end loop;
    
        wb_req.adr <= (others => '0');
        wb_req.dat <= (others => '0');
        wb_req.we <= '0';
        wb_req.sel <= (others => '0');
        wb_req.stb <= '0';
        wb_req.cyc <= '0';

        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).data <= (others => '0');
            bus_resp(i).address <= (others => '0');
            bus_resp(i).rw <= '0';
            bus_resp(i).valid <= '0';
        end loop;
        case R_wb_state is
        when IDLE =>
            
        when READ_LOCK =>
            wb_req.adr <= R_active_bus_reqests(R_lock_bus_id).address;
            wb_req.sel <= wb_req_sel_o;
            wb_req.stb <= '1';
            wb_req.cyc <= '1';
            
            bus_resp(R_lock_bus_id).data <= wb_resp_dat_i;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= wb_resp.ack;
        when WRITE_LOCK =>
            wb_req.adr <= R_active_bus_reqests(R_lock_bus_id).address;
            wb_req.dat <= wb_req_dat_o;
            wb_req.we <= R_active_bus_reqests(R_lock_bus_id).rw;
            wb_req.sel <= wb_req_sel_o;
            wb_req.stb <= '1';
            wb_req.cyc <= '1';

            bus_resp(R_lock_bus_id).data <= wb_resp_dat_i;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= wb_resp.ack;
        when others =>
        end case;
    end process;

    P_wb_req_dat_o_gen : process(R_active_bus_reqests, R_lock_bus_id)
    begin
        wb_req_dat_o <= (others => '0');
        wb_req_sel_o <= (others => '0');
        case R_active_bus_reqests(R_lock_bus_id).data_size is
        when "00" =>
            case R_active_bus_reqests(R_lock_bus_id).address(1 downto 0) is
            when "00" =>
                wb_req_dat_o(7 downto 0) <= R_active_bus_reqests(R_lock_bus_id).data(7 downto 0);
                wb_req_sel_o <= "0001";
            when "01" =>
                wb_req_dat_o(15 downto 8) <= R_active_bus_reqests(R_lock_bus_id).data(7 downto 0);
                wb_req_sel_o <= "0010";
            when "10" =>
                wb_req_dat_o(23 downto 16) <= R_active_bus_reqests(R_lock_bus_id).data(7 downto 0);
                wb_req_sel_o <= "0100";
            when "11" =>
                wb_req_dat_o(31 downto 24) <= R_active_bus_reqests(R_lock_bus_id).data(7 downto 0);
                wb_req_sel_o <= "1000";
            when others =>
            end case;
        when "01" =>
            case R_active_bus_reqests(R_lock_bus_id).address(1) is
            when '0' =>
                wb_req_dat_o(15 downto 0) <= R_active_bus_reqests(R_lock_bus_id).data(15 downto 0);
                wb_req_sel_o <= "0011";
            when '1' =>
                wb_req_dat_o(31 downto 16) <= R_active_bus_reqests(R_lock_bus_id).data(15 downto 0);
                wb_req_sel_o <= "1100";
            when others =>
            end case;
        when "10" =>
            wb_req_dat_o(31 downto 0) <= R_active_bus_reqests(R_lock_bus_id).data(31 downto 0);
            wb_req_sel_o <= "1111";
        when others =>
        end case; 
    end process;

    P_wb_req_dat_i_gen : process(R_active_bus_reqests, R_lock_bus_id, wb_resp)
    begin
        wb_resp_dat_i <= (others => '0');
        case R_active_bus_reqests(R_lock_bus_id).data_size is
        when "00" =>
            case R_active_bus_reqests(R_lock_bus_id).address(1 downto 0) is
            when "00" =>
                wb_resp_dat_i(7 downto 0) <= wb_resp.dat(7 downto 0);
            when "01" =>
                wb_resp_dat_i(7 downto 0) <= wb_resp.dat(15 downto 8);
            when "10" =>
                wb_resp_dat_i(7 downto 0) <= wb_resp.dat(23 downto 16);
            when "11" =>
                wb_resp_dat_i(7 downto 0) <= wb_resp.dat(31 downto 24);
            when others =>
            end case;
        when "01" =>
            case R_active_bus_reqests(R_lock_bus_id).address(1) is
            when '0' =>
                wb_resp_dat_i(15 downto 0) <= wb_resp.dat(15 downto 0);
            when '1' =>
                wb_resp_dat_i(15 downto 0) <= wb_resp.dat(31 downto 16);
            when others =>
            end case;
        when "10" =>
            wb_resp_dat_i(31 downto 0) <= wb_resp.dat(31 downto 0);
        when others =>
        end case; 
    end process;
end rtl;



