library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use WORK.CPU_PKG.ALL;

entity cpu_core is
    port(
        -- External bus / cache signals
        bus_req_fe     : out T_wishbone_req;
        bus_resp_fe    : in T_wishbone_resp;
        bus_req_lsu    : out T_wishbone_req;
        bus_resp_lsu   : in T_wishbone_resp;
    
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
    I_gen_icache: if ICACHE_ENABLE = true generate
        I_icache: entity work.cache
        generic map(ENABLE_WRITE => false,
                    ENABLE_UNCACHED_ADDR_RANGE => false,
                    UNCACHED_ADDR_RANGE => X"0",
                    ADDRESS_WIDTH => 32,
                    ASSOCIATIVITY => 1,
                    BYTES_PER_WORD => 4,
                    WORDS_PER_CACHELINE => 4,
                    SIZE_BYTES => 16384)
        port map(clk => clk,
                 reset => reset,
                 cpu_bus_req => fe_bus_req,
                 cpu_bus_resp => fe_bus_resp,
                 ext_bus_req => bus_req_fe,
                 ext_bus_resp => bus_resp_fe);
    else generate
        I_icache_bridge: entity work.internal_to_wishbone_bridge
        port map(
            clk => clk,
            reset => reset,
            internal_bus_req => fe_bus_req,
            internal_bus_resp => fe_bus_resp,
            wishbone_bus_req => bus_req_fe,
            wishbone_bus_resp => bus_resp_fe
        );
    end generate;
    
    I_gen_dcache: if DCACHE_ENABLE = true generate
        I_dcache: entity work.cache
        generic map(ENABLE_WRITE => true,
                    ENABLE_UNCACHED_ADDR_RANGE => true,
                    UNCACHED_ADDR_RANGE => X"F",
                    ADDRESS_WIDTH => 32,
                    ASSOCIATIVITY => 1,
                    BYTES_PER_WORD => 4,
                    WORDS_PER_CACHELINE => 4,
                    SIZE_BYTES => 512)
        port map(clk => clk,
                 reset => reset,
                 cpu_bus_req => lsu_bus_req,
                 cpu_bus_resp => lsu_bus_resp,
                 ext_bus_req => bus_req_lsu,
                 ext_bus_resp => bus_resp_lsu);
    else generate
        I_dcache_bridge: entity work.internal_to_wishbone_bridge
        port map(
            clk => clk,
            reset => reset,
            internal_bus_req => lsu_bus_req,
            internal_bus_resp => lsu_bus_resp,
            wishbone_bus_req => bus_req_lsu,
            wishbone_bus_resp => bus_resp_lsu
        );
    end generate;

    fe_inst : entity work.front_end
    port map(clk                => clk,
             reset              => reset,
             uop_out            => uop,
             stall_be           => stall_be,
             cdb_in             => cdb,
             bus_req            => fe_bus_req,
             bus_resp           => fe_bus_resp);

    be_inst : entity work.back_end
    port map(uop_1       => uop,
             stall_be    => stall_be,
             cdb_out     => cdb,
             bus_req     => lsu_bus_req,
             bus_resp    => lsu_bus_resp,
             clk         => clk,
             reset       => reset);
end rtl;
