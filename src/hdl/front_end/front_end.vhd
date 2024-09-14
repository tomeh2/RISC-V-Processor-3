library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity front_end is
    port(
        clk             : in std_logic;
        reset           : in std_logic;
    
        bus_req         : out T_bus_request;
        bus_resp        : in T_bus_response;
        bus_ready       : in std_logic
    );
end front_end;

architecture rtl of front_end is
    signal R_program_counter : unsigned(ADDR_WIDTH - 1 downto 0);
    signal decoded_uop : T_uop;
begin
    P_pc_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_program_counter <= to_unsigned(0, ADDR_WIDTH);
            else
                if bus_resp.valid = '1' then
                    R_program_counter <= R_program_counter + 4;
                end if;
            end if;
        end if;
    end process;

    bus_req.address <= std_logic_vector(R_program_counter);
    bus_req.tag <= (others => '0');
    bus_req.valid <= not reset;
    
    I_instr_dec : entity work.instruction_decoder
    port map(instruction            => bus_resp.data,
             instruction_valid      => bus_resp.valid,
             pc                     => R_program_counter,
             invalid_instruction    => open,
             decoded_uop            => decoded_uop);
end rtl;
