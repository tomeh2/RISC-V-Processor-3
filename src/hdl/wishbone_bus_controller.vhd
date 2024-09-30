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

    signal wb_resp_data_masked : std_logic_vector(31 downto 0);
    signal wb_resp_data_shifted : std_logic_vector(31 downto 0);
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

    process(R_active_bus_reqests, R_lock_bus_id, R_wb_state, wb_resp.ack, wb_resp_data_shifted)
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
            wb_req.adr <= R_active_bus_reqests(R_lock_bus_id).address & "00";
            wb_req.dat <= R_active_bus_reqests(R_lock_bus_id).data;
            wb_req.we <= R_active_bus_reqests(R_lock_bus_id).rw;
            wb_req.sel <= R_active_bus_reqests(R_lock_bus_id).data_mask;
            wb_req.stb <= '1';
            wb_req.cyc <= '1';
            
            bus_resp(R_lock_bus_id).data <= wb_resp_data_shifted;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= wb_resp.ack;
        when WRITE_LOCK =>
            wb_req.adr <= R_active_bus_reqests(R_lock_bus_id).address & "00";
            wb_req.dat <= R_active_bus_reqests(R_lock_bus_id).data;
            wb_req.we <= R_active_bus_reqests(R_lock_bus_id).rw;
            wb_req.sel <= R_active_bus_reqests(R_lock_bus_id).data_mask;
            wb_req.stb <= '1';
            wb_req.cyc <= '1';

            bus_resp(R_lock_bus_id).data <= wb_resp_data_shifted;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= wb_resp.ack;
        when others =>
        end case;
    end process;

    P_process_resp_data : process(R_active_bus_reqests, wb_resp.dat, wb_resp_data_masked, R_lock_bus_id)
        variable dmask_trailing_zeroes : natural range 0 to 3;
    begin
        for i in 0 to 3 loop
            if R_active_bus_reqests(R_lock_bus_id).data_mask(i) = '1' then
                wb_resp_data_masked((i + 1) * 8 - 1 downto i * 8) <= wb_resp.dat((i + 1) * 8 - 1 downto i * 8); 
            else
                wb_resp_data_masked((i + 1) * 8 - 1 downto i * 8) <= (others => '0');
            end if;
        end loop;

        dmask_trailing_zeroes := 0;
        for i in 0 to 3 loop
            if R_active_bus_reqests(R_lock_bus_id).data_mask(i) = '0' then
                dmask_trailing_zeroes := i;
            end if;
        end loop;

        wb_resp_data_shifted <= wb_resp_data_masked;
        for i in 3 downto 1 loop
            if dmask_trailing_zeroes = i then
                wb_resp_data_shifted(31 downto (4 - i) * 8) <= (others => '0');
                wb_resp_data_shifted((4 - i) * 8 - 1 downto 0) <= wb_resp_data_masked(31 downto i * 8);
            end if;
        end loop;
    end process;
end rtl;



