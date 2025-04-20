library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

entity wishbone_arbiter is
    generic(
        NUM_MASTERS : natural
    );
    port(
        -- CPU SIDE BUS
        bus_req : in T_wishbone_req_array(0 to NUM_MASTERS - 1);
        bus_resp : out T_wishbone_resp_array(0 to NUM_MASTERS - 1);

        wb_req : out T_wishbone_req;
        wb_resp : in T_wishbone_resp;

        clk : in std_logic;
        reset : in std_logic
    );
end wishbone_arbiter;

architecture rtl of wishbone_arbiter is
    type T_wb_state is (IDLE, READ_LOCK, WRITE_LOCK, RESPONSE);
    signal R_wb_state : T_wb_state;
    signal R_locked_bus_id : natural range 0 to NUM_MASTERS - 1;

    signal R_requests: T_wishbone_req_array(0 to NUM_MASTERS - 1);
    signal R_response: T_wishbone_resp;
    signal master_bus_request_valid: std_logic;
    signal master_bus_request_id: natural range 0 to NUM_MASTERS - 1;
begin
    P_pick_master_bus: process(R_requests)
        variable master_bus_id: natural range 0 to NUM_MASTERS - 1;
        variable req_valid: std_logic;
    begin
        master_bus_id := 0;
        req_valid := '0';
            -- Lower ID -> Higher Priority
        for i in NUM_MASTERS - 1 downto 0 loop
            if R_requests(i).stb = '1' and R_requests(i).cyc = '1' then
                master_bus_id := i;
                req_valid := '1';
            end if;
        end loop;
        master_bus_request_id <= master_bus_id;
        master_bus_request_valid <= req_valid;
    end process;

    process(clk)
        
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_wb_state <= IDLE;

                for i in 0 to NUM_MASTERS - 1 loop
                    R_requests(i).stb <= '0';
                    R_requests(i).cyc <= '0';
                end loop;
            else
                R_response.ack <= '0';
            
                case R_wb_state is
                when IDLE =>
                    for i in 0 to NUM_MASTERS - 1 loop
                        R_requests(i) <= bus_req(i);
                    end loop;
                
                    if master_bus_request_valid = '1' then
                        R_locked_bus_id <= master_bus_request_id;
                        if R_requests(master_bus_request_id).we = '1' then
                            R_wb_state <= WRITE_LOCK;
                        else
                            R_wb_state <= READ_LOCK;
                        end if;
                    end if;
                when READ_LOCK =>
                    if wb_resp.ack = '1' then
                        R_wb_state <= RESPONSE;

                        R_response <= wb_resp;

                        R_requests(R_locked_bus_id).stb <= '0';
                        R_requests(R_locked_bus_id).cyc <= '0';
                    end if;
                when WRITE_LOCK =>
                    if wb_resp.ack = '1' then
                        R_wb_state <= RESPONSE;

                        R_response <= wb_resp;

                        R_requests(R_locked_bus_id).stb <= '0';
                        R_requests(R_locked_bus_id).cyc <= '0';
                    end if;
                when RESPONSE =>
                    R_wb_state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    process(R_wb_state, R_requests, R_locked_bus_id, R_response)
    begin
        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).ack <= '0';
        end loop;

        wb_req.stb <= '0';
        wb_req.cyc <= '0';
        case R_wb_state is
        when IDLE =>
            
        when READ_LOCK =>
            wb_req <= R_requests(R_locked_bus_id);
        when WRITE_LOCK =>
            wb_req <= R_requests(R_locked_bus_id);
        when RESPONSE =>
            bus_resp(R_locked_bus_id) <= R_response;
        end case;
    end process;
end rtl;



