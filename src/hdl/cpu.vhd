library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity cpu is
    port(
        bus_req     : out T_bus_request;
        bus_resp    : in T_bus_response;
        bus_ready   : in std_logic;
    
        clk         : in std_logic;
        reset       : in std_logic
    );
end cpu;

architecture rtl of cpu is

begin
    cpu_core_0_inst : entity work.cpu_core
    port map(bus_req     => bus_req,
             bus_resp    => bus_resp,
             bus_ready   => bus_ready,
             clk         => clk,
             reset       => reset); 

end rtl;
