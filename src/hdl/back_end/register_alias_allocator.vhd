library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity register_alias_allocator is
    generic(
        MAX_SNAPSHOTS : integer;
        MASK_LENGTH : integer
    );
    port(
        -- Next tag available for allocation
        get_tag : out std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        get_enable : in std_logic;
        -- Tag which will be freed so that it can be allocated in the future
        put_tag : in std_logic_vector(PHYS_REG_ADDR_WIDTH - 1 downto 0);
        put_enable : in std_logic;
        -- Snapshot control
        take_snapshot_enable : in std_logic;
        take_snapshot_index : in integer;
        recover_snapshot_enable : in std_logic;
        recover_snapshot_index : in integer;

        -- Returns whether the RAA has any registers left to allocate. A value
        -- of 1 indicates that this RAA doesn't have any free registers left
        -- and any value given by get_tag is invalid
        empty : out std_logic;

        clk : in std_logic;
        reset : in std_logic
    );
end register_alias_allocator;

architecture rtl of register_alias_allocator is
    type T_reg_usage_mask is array (0 to MAX_SNAPSHOTS - 1) of std_logic_vector(MASK_LENGTH - 1 downto 0);
    -- This memory keeps track of all tags that have been allocated after the
    -- corresponding speculative instruction. If the instruction mispredicts
    -- then we can just use the generated mask to deallocate all registers that
    -- were wrongly allocated. This method generates much simpler logic then
    -- if we kept full snapshots of the usage masks (and if we need to keep
    -- updating them)
    signal M_snapshots : T_reg_usage_mask;
    signal R_active_mask : std_logic_vector(MASK_LENGTH - 1 downto 0);
    signal empty_n : std_logic;

    signal free_tag_index : integer := 0;
begin
    process(R_active_mask)
    begin
        F_priority_encoder(R_active_mask, free_tag_index, empty_n, true);
    end process;

    P_raa_cntrl : process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                R_active_mask <= (others => '1');
                -- Register with tag 0 is always 0, so never allocate it as a
                -- destination register
                R_active_mask(0) <= '0';
            else
                if recover_snapshot_enable = '1' then
                    R_active_mask <= R_active_mask or M_snapshots(recover_snapshot_index);
                else
                    -- Snapshot logic
                    if take_snapshot_enable = '1' then
                        M_snapshots(take_snapshot_index) <= (others => '0');
                    end if;

                    if get_enable = '1' and free_tag_index /= 0 then
                        -- Find a free tag index using a priority encoder
                        R_active_mask(free_tag_index) <= '0';
                        for i in 0 to MAX_SNAPSHOTS - 1 loop
                            M_snapshots(i)(free_tag_index) <= '1'; 
                        end loop;
                    end if;
    
                    if put_enable = '1' then
                        R_active_mask(F_vec_to_int(put_tag)) <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    empty <= not empty_n;
    get_tag <= F_int_to_vec(free_tag_index, PHYS_REG_ADDR_WIDTH) when get_enable = '1' else (others => '0');
end rtl;

--architecture rtl of register_alias_allocator is
--    type T_reg_usage_mask is array (0 to MAX_SNAPSHOTS - 1) of std_logic_vector(MASK_LENGTH - 1 downto 0);
--    signal M_snapshots : T_reg_usage_mask;
--    signal R_active_mask : std_logic_vector(MASK_LENGTH - 1 downto 0);

--    signal free_tag_index : integer;
--begin
--    free_tag_index <= F_priority_encoder(R_active_mask);

--    P_raa_cntrl : process(clk)
--        variable free_tag_index : integer;
--        variable active_mask_next : std_logic_vector(MASK_LENGTH - 1 downto 0);
--    begin
--        if rising_edge(clk) then
--            if reset = '1' then
--                R_active_mask <= (others => '0');
--                -- Register with tag 0 is always 0, so never allocate it as a
--                -- destination register
--                R_active_mask(0) <= '1';
--            else
--                if recover_snapshot_enable = '1' then
--                    R_active_mask <= M_snapshots(recover_snapshot_index);
--                else
--                    -- Snapshot logic
--                    if take_snapshot_enable = '1' then
--                        -- This logic makes sure that the shapshot has the
--                        -- current instruction's tag bit cleared if the
--                        -- instruction 
--                        active_mask_next := R_active_mask;
--                        if free_tag_index /= 0 then
--                            active_mask_next(free_tag_index) := '0';
--                        end if;
--                        M_snapshots(take_snapshot_index) <= active_mask_next;

--                        if put_enable = '1' then
--                            for i in 0 to MAX_SNAPSHOTS - 1 loop
--                                if i /= take_snapshot_index then
--                                    M_snapshots(i)(F_vec_to_int(put_tag)) <= '1';
--                                end if;
--                            end loop;
--                        end if;
--                    else
--                        if put_enable = '1' then
--                            for i in 0 to MAX_SNAPSHOTS - 1 loop
--                                M_snapshots(i)(F_vec_to_int(put_tag)) <= '1';
--                            end loop;
--                        end if;
--                    end if;

--                    if get_enable = '1' and free_tag_index /= 0 then
--                        -- Find a free tag index using a priority encoder
--                        R_active_mask(free_tag_index) <= '0';
--                    end if;

--                    if put_enable = '1' then
--                        R_active_mask(F_vec_to_int(put_tag)) <= '1';
--                    end if;
--                end if;
--            end if;
--        end if;
--    end process;
--end rtl;
