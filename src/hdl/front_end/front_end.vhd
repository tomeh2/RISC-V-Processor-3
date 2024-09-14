library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity front_end is
    port(
        clk             : in std_logic;
        reset           : in std_logic;

        cdb_in          : in T_uop;
        stall_be        : in std_logic;

        bus_req         : out T_bus_request;
        bus_resp        : in T_bus_response;
        bus_ready       : in std_logic
    );
end front_end;

architecture rtl of front_end is
    signal fetch_fifo_instruction : std_logic_vector(31 downto 0);
    signal fetch_fifo_full : std_logic;
    signal fetch_fifo_empty : std_logic;

    signal R_pipeline_0_instr : std_logic_vector(31 downto 0);
    signal R_pipeline_0_pc : unsigned(31 downto 0);
    signal R_pipeline_0_valid : std_logic;

    signal stall_fetch : std_logic;

    signal R_program_counter : unsigned(ADDR_WIDTH - 1 downto 0);
    signal decoded_uop : T_uop;
begin
    I_fetch_fifo : entity work.fifo
    generic map(BITS_PER_ENTRY => 32,
                ENTRIES => 4)
    port map(clk        => clk,
             reset      => reset,
             data_in    => bus_resp.data,
             data_out   => fetch_fifo_instruction,
             get_en     => '0',
             put_en     => bus_resp.valid,
             full       => fetch_fifo_full,
             empty      => fetch_fifo_empty);

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
    bus_req.valid <= not reset and not fetch_fifo_full;
    

    
    I_instr_dec : entity work.instruction_decoder
    port map(instruction            => fetch_fifo_instruction,
             instruction_valid      => not fetch_fifo_empty,
             pc                     => (others => '0'),
             invalid_instruction    => open,
             decoded_uop            => decoded_uop);
end rtl;
