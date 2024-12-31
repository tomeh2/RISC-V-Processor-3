library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

-- VERY WIP

entity csr is
    port(
        clk: in std_logic;
        reset: in std_logic;

        uop_in: in T_uop;
        retired_uop_in: in T_retired_uop;
        csr_value: out std_logic_vector(31 downto 0);

        cdb_in: in T_uop;
        -- ============
        -- FLOW CONTROL
        -- ============
        stall_in: in std_logic;
        stall_out: out std_logic
    );
end csr;

architecture rtl of csr is
    signal R_csr_cycle: unsigned(63 downto 0);
    signal R_csr_instret: unsigned(63 downto 0);
    -- Branches executed
    signal R_csr_brexec: unsigned(63 downto 0);
    -- Branches mispredicted
    signal R_csr_brmispred: unsigned(63 downto 0);

    signal csr_address: unsigned(7 downto 0);
begin
    csr_address <= unsigned(uop_in.immediate(7 downto 0));

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_csr_cycle <= (others => '0');
                R_csr_instret <= (others => '0');
                R_csr_brexec <= (others => '0');
                R_csr_brmispred <= (others => '0');
            else
                if CSR_PERFCNTR_ENABLE = true then
                    R_csr_cycle <= R_csr_cycle + 1;

                    if retired_uop_in.valid = '1' then
                        R_csr_instret <= R_csr_instret + 1;
                    end if;

                    if cdb_in.valid = '1' then
                        if cdb_in.branch_mask /= "0000" then
                            R_csr_brexec <= R_csr_brexec + 1;
                        end if;

                        if cdb_in.branch_mispredicted = '1' then
                            R_csr_brmispred <= R_csr_brmispred + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(csr_address, R_csr_cycle, R_csr_instret, R_csr_brexec, R_csr_brmispred)
    begin
        csr_value <= (others => '0');
        if CSR_PERFCNTR_ENABLE = true then
            case csr_address is
            when X"00" =>
                csr_value <= std_logic_vector(R_csr_cycle(31 downto 0));
            when X"02" =>
                csr_value <= std_logic_vector(R_csr_instret(31 downto 0));
            when X"03" =>
                csr_value <= std_logic_vector(R_csr_brexec(31 downto 0));
            when X"04" =>
                csr_value <= std_logic_vector(R_csr_brmispred(31 downto 0));
            when X"80" =>
                csr_value <= std_logic_vector(R_csr_cycle(63 downto 32));
            when X"82" =>
                csr_value <= std_logic_vector(R_csr_instret(63 downto 32));
            when X"83" =>
                csr_value <= std_logic_vector(R_csr_brexec(63 downto 32));
            when X"84" =>
                csr_value <= std_logic_vector(R_csr_brmispred(63 downto 32));
            when others =>
            end case;
        end if;
    end process;

    stall_out <= '0';
end rtl;
