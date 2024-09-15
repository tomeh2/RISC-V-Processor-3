library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity cpu_core is
    port(
        -- External bus / cache signals
        bus_req     : out T_bus_request;
        bus_resp    : in T_bus_response;
        bus_ready   : in std_logic;
    
        clk         : in std_logic;
        reset       : in std_logic
    );
end cpu_core;

architecture rtl of cpu_core is
    signal uop : T_uop;
    signal stall_be : std_logic;
begin
    fe_inst : entity work.front_end
    port map(clk        => clk,
             reset      => reset,
             uop_out    => uop,
             stall_be   => stall_be,
             cdb_in     => UOP_ZERO,
             bus_req    => bus_req,
             bus_resp   => bus_resp,
             bus_ready  => bus_ready);

    be_inst : entity work.back_end
    port map(uop_1       => uop,
             stall_be    => stall_be,
             bus_req     => open,
             bus_resp    => BUS_RESP_ZERO,
             bus_ready   => bus_ready,
             clk         => clk,
             reset       => reset);
end rtl;
