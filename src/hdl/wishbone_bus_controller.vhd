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
        bus_ready : out std_logic;

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
    
    signal R_addr : std_logic_vector(31 downto 0);
    signal R_wr_data : std_logic_vector(31 downto 0);
    signal R_rd_data : std_logic_vector(31 downto 0);
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_wb_state <= IDLE;
            else
                case R_wb_state is
                when IDLE =>
                    for i in NUM_MASTERS - 1 downto 0 loop
                        if bus_req(i).valid = '1' then
                            R_addr <= bus_req(i).address;
                            R_wr_data <= bus_req(i).data;
                            
                            if bus_req(i).rw = '1' then
                                R_wb_state <= WRITE_LOCK;
                            else
                                R_wb_state <= READ_LOCK;
                            end if;
                            R_lock_bus_id <= i;
                        end if;
                    end loop;
                when READ_LOCK =>
                    if ack_i = '1' then
                        R_wb_state <= IDLE;
                        R_lock_bus_id <= 0;
                    end if;
                when WRITE_LOCK =>
                    if ack_i = '1' then
                        R_wb_state <= IDLE;
                        R_lock_bus_id <= 0;
                    end if;
                end case;
            end if;
        end if;
    end process;

    process(R_wb_state, ack_i, dat_i, R_addr)
    begin
        sel_o <= "0000";
        stb_o <= '0';
        cyc_o <= '0';
        we_o <= '0';
        bus_ready <= '1';
        for i in 0 to NUM_MASTERS - 1 loop
            bus_resp(i).rw <= '0';
            bus_resp(i).valid <= '0';
            bus_resp(i).address <= (others => '0');
        end loop;

        case R_wb_state is
        when IDLE =>
            
        when READ_LOCK =>
            bus_ready <= '0';
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';

            bus_resp(R_lock_bus_id).data <= dat_i;
            bus_resp(R_lock_bus_id).rw <= '0';
            bus_resp(R_lock_bus_id).valid <= ack_i;
            bus_resp(R_lock_bus_id).address <= R_addr;
        when WRITE_LOCK =>
            bus_ready <= '0';
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';
            we_o <= '1';

            bus_resp(R_lock_bus_id).rw <= '1';
            bus_resp(R_lock_bus_id).valid <= ack_i;
            bus_resp(R_lock_bus_id).address <= R_addr;
        when others =>
            bus_ready <= '0';
        end case;
    end process;
    adr_o <= R_addr;
    dat_o <= R_wr_data;
end rtl;
