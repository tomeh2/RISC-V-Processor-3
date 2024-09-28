library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity cpu_core is
    port(
        -- External bus / cache signals
        bus_req_fe     : out T_bus_request;
        bus_resp_fe    : in T_bus_response;
        bus_req_lsu    : out T_bus_request;
        bus_resp_lsu   : in T_bus_response;
    
        clk            : in std_logic;
        reset          : in std_logic
    );
end cpu_core;

architecture rtl of cpu_core is
    signal uop : T_uop;
    signal cdb : T_uop;
    signal stall_be : std_logic;
begin
    fe_inst : entity work.front_end
    port map(clk        => clk,
             reset      => reset,
             uop_out    => uop,
             stall_be   => stall_be,
             cdb_in     => cdb,
             bus_req    => bus_req_fe,
             bus_resp   => bus_resp_fe);

    be_inst : entity work.back_end
    port map(uop_1       => uop,
             stall_be    => stall_be,
             cdb_out     => cdb,
             bus_req     => bus_req_lsu,
             bus_resp    => bus_resp_lsu,
             clk         => clk,
             reset       => reset);
end rtl;
