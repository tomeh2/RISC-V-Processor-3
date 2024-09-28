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

        adr_o : out std_logic_vector(31 downto 0);
        dat_i : in std_logic_vector(31 downto 0);
        dat_o : out std_logic_vector(31 downto 0);
        we_o : out std_logic;
        sel_o : out std_logic_vector(3 downto 0);
        stb_o : out std_logic;
        ack_i : in std_logic;
        cyc_o : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end wishbone_bus_controller;

architecture rtl of wishbone_bus_controller is
    type T_wb_state is (IDLE, READ_LOCK, WRITE_LOCK);
    signal R_wb_state : T_wb_state;
    signal R_lock_bus_id : natural range 0 to NUM_MASTERS - 1;
    
    signal R_active_bus_reqests : T_bus_request_array(0 to NUM_MASTERS - 1);
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

                if ack_i = '1' and R_wb_state /= IDLE then
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
                    if ack_i = '1' then
                        R_wb_state <= IDLE;
                    end if;
                when WRITE_LOCK =>
                    if ack_i = '1' then
                        R_wb_state <= IDLE;
                    end if;
                end case;
            end if;
        end if;
    end process;

    process(R_active_bus_reqests, R_lock_bus_id, R_wb_state, dat_i, ack_i)
    begin
        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).ready <= not R_active_bus_reqests(i).valid;
        end loop;
    
        adr_o <= (others => '0');
        dat_o <= (others => '0');
        we_o <= '0';
        sel_o <= (others => '0');
        stb_o <= '0';
        cyc_o <= '0';

        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).data <= (others => '0');
            bus_resp(i).address <= (others => '0');
            bus_resp(i).rw <= '0';
            bus_resp(i).valid <= '0';
        end loop;
        case R_wb_state is
        when IDLE =>
            
        when READ_LOCK =>
            adr_o <= R_active_bus_reqests(R_lock_bus_id).address;
            dat_o <= R_active_bus_reqests(R_lock_bus_id).data;
            we_o <= R_active_bus_reqests(R_lock_bus_id).rw;
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';
            
            bus_resp(R_lock_bus_id).data <= dat_i;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= ack_i;
        when WRITE_LOCK =>
            adr_o <= R_active_bus_reqests(R_lock_bus_id).address;
            dat_o <= R_active_bus_reqests(R_lock_bus_id).data;
            we_o <= R_active_bus_reqests(R_lock_bus_id).rw;
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';

            bus_resp(R_lock_bus_id).data <= dat_i;
            bus_resp(R_lock_bus_id).address <= R_active_bus_reqests(R_lock_bus_id).address;
            bus_resp(R_lock_bus_id).rw <= R_active_bus_reqests(R_lock_bus_id).rw;
            bus_resp(R_lock_bus_id).valid <= ack_i;
        when others =>
        end case;
    end process;
end rtl;
