-- RISC-V Processor 3 Planned Features
-- 1) RV32GC instruction set (RV32IA minimum)
-- 2) Speculative branches
-- 3) Speculative LSU
-- 4) Memory virtualization
-- 5) FPU
-- 6) AXI Bus with bulk transfers
-- 7) I-Cache
-- 8) D-Cache
-- 9) Dual-Issue superscalar
-- 10) Register renaming
-- 11) Potentially multi-core

-- This processor relies quite heavily on the synthesis engine's ability to
-- trim unused signals to simplify connections between modules. Modules
-- therefore take as inputs whole data structures and not just parts that
-- they need, but only use parts that are relevant to them.
-- This might change in the future if it turn out to work poorly

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity top is
    port(
        CLK100MHZ : in std_logic;
        CPU_RESETN : in std_logic;
        -- UART
        UART_TXD : in std_logic;
        UART_RXD : out std_logic;
        -- 7 SEGMENT DISPLAY
        CA: out std_logic;
        CB: out std_logic;
        CC: out std_logic;
        CD: out std_logic;
        CE: out std_logic;
        CF: out std_logic;
        CG: out std_logic;
        DP: out std_logic;
        AN: out std_logic_vector(7 downto 0);
        -- GPIO
        SW: in std_logic_vector(15 downto 0);
        LED: out std_logic_vector(15 downto 0);
        -- I2C TEMP SENSOR
        TMP_SCL: inout std_logic;
        TMP_SDA: inout std_logic;
        TMP_INT: in std_logic;
        TMP_CT: in std_logic;
        -- JD PMOD HEADER
        JD1: inout std_logic;
        JD2: inout std_logic
    );
end top;

architecture rtl of top is
    signal pll_clk, pll_locked: std_logic;
    signal reset: std_logic;
    signal gpio_out: std_logic_vector(31 downto 0);
    
    signal i2c_sda, i2c_scl: std_logic;
    signal sda_dbg, scl_dbg: std_logic;
    
    component clk_wiz_0
    port
     (-- Clock in ports
      -- Clock out ports
      clk_out1          : out    std_logic;
      -- Status and control signals
      locked            : out    std_logic;
      clk_in1           : in     std_logic
     );
    end component;
begin
    reset <= (not CPU_RESETN) or (not pll_locked);
    I_soc : entity work.soc
    port map(clk => pll_clk,
             reset => reset,
             sevseg_anodes(0) => AN(4),
             sevseg_anodes(1) => AN(5),
             sevseg_anodes(2) => AN(6),
             sevseg_anodes(3) => AN(7),
             sevseg_anodes(4) => AN(0),
             sevseg_anodes(5) => AN(1),
             sevseg_anodes(6) => AN(2),
             sevseg_anodes(7) => AN(3),
             sevseg_cathodes(0) => CA,
             sevseg_cathodes(1) => CB,
             sevseg_cathodes(2) => CC,
             sevseg_cathodes(3) => CD,
             sevseg_cathodes(4) => CE,
             sevseg_cathodes(5) => CF,
             sevseg_cathodes(6) => CG,
             sevseg_cathodes(7) => DP,
             uart_tx => UART_RXD,
             uart_rx => UART_TXD,
             gpio_in(15 downto 0) => SW,
             gpio_in(31 downto 16) => X"0000",
             gpio_out => gpio_out,
             i2c1_sda => i2c_sda,
             i2c1_scl => i2c_scl,
             sda_debug => sda_dbg,
             scl_debug => scl_dbg);
    LED <= gpio_out(15 downto 0);

    your_instance_name : clk_wiz_0
    port map (-- Clock out ports  
              clk_out1 => pll_clk,
              -- Status and control signals                
              locked => pll_locked,
              -- Clock in ports
              clk_in1 => CLK100MHZ
 );

    TMP_SDA <= i2c_sda;
    TMP_SCL <= i2c_scl;
    --JD1 <= sda_dbg;
    --JD2 <= scl_dbg;
end rtl;
