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
    signal icache_cancel_all : std_logic;
    signal stall_be : std_logic;
    signal stall_icache: std_logic;
    signal fe_bus_req: T_bus_request;
    signal fe_bus_resp: T_bus_response;
    signal lsu_bus_req: T_bus_request;
    signal lsu_bus_resp: T_bus_response;
begin
    I_icache: entity work.cache
    generic map(ADDRESS_WIDTH => 32,
                ASSOCIATIVITY => 1,
                BYTES_PER_WORD => 4,
                WORDS_PER_CACHELINE => 4,
                SIZE_BYTES => 8192)
    port map(clk => clk,
             reset => reset,
             cancel_all => icache_cancel_all,
             stall_out => stall_icache,
             cpu_bus_req => fe_bus_req,
             cpu_bus_resp => fe_bus_resp,
             ext_bus_req => bus_req_fe,
             ext_bus_resp => bus_resp_fe);

--    I_dcache: entity work.cache
--    generic map(ADDRESS_WIDTH => 32,
--                ASSOCIATIVITY => 1,
--                BYTES_PER_WORD => 4,
--                WORDS_PER_CACHELINE => 4,
--                NUM_BLOCKS => 4)
--    port map(clk => clk,
--             reset => reset,
--             cancel_all => '0',
--             stall_out => open,
--             cpu_bus_req => lsu_bus_req,
--             cpu_bus_resp => lsu_bus_resp,
--             ext_bus_req => bus_req_lsu,
--             ext_bus_resp => bus_resp_lsu);

    fe_inst : entity work.front_end
    port map(clk                => clk,
             reset              => reset,
             uop_out            => uop,
             stall_be           => stall_be,
             icache_cancel_all  => icache_cancel_all,
             icache_ready       => not stall_icache,
             cdb_in             => cdb,
             bus_req            => fe_bus_req,
             bus_resp           => fe_bus_resp);

    be_inst : entity work.back_end
    port map(uop_1       => uop,
             stall_be    => stall_be,
             cdb_out     => cdb,
             bus_req     => bus_req_lsu,
             bus_resp    => bus_resp_lsu,
             clk         => clk,
             reset       => reset);
end rtl;
