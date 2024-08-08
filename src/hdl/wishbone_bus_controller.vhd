library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.CPU_PKG.ALL;

entity wishbone_bus_controller is
    port(
        -- CPU SIDE BUS
        bus_req : in T_bus_request;
        bus_resp : out T_bus_response;
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
    
    signal R_addr : std_logic_vector(31 downto 0);
    signal R_tag : unsigned(7 downto 0);
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
                    if bus_req.valid = '1' then
                        R_addr <= bus_req.address;
                        R_wr_data <= bus_req.data;
                        R_tag <= bus_req.tag;

                        if bus_req.rw = '1' then
                            R_wb_state <= WRITE_LOCK;
                        else
                            R_wb_state <= READ_LOCK;
                        end if;
                    end if;
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

    process(R_wb_state, ack_i, R_tag)
    begin
        sel_o <= "0000";
        stb_o <= '0';
        cyc_o <= '0';
        we_o <= '0';
        bus_ready <= '1';

        bus_resp.rw <= '0';
        bus_resp.valid <= '0';
        bus_resp.tag <= (others => '0');
        case R_wb_state is
        when IDLE =>
            
        when READ_LOCK =>
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';

            bus_resp.data <= dat_i;
            bus_resp.rw <= '0';
            bus_resp.valid <= ack_i;
            bus_resp.tag <= R_tag;
        when WRITE_LOCK =>
            sel_o <= "1111";
            stb_o <= '1';
            cyc_o <= '1';
            we_o <= '1';

            bus_resp.rw <= '1';
            bus_resp.valid <= ack_i;
            bus_resp.tag <= R_tag;
        when others =>
            
        end case;
    end process;
    adr_o <= R_addr;
    dat_o <= R_wr_data;
end rtl;
