library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use WORK.CPU_PKG.ALL;

entity instruction_decoder is
    port(
        instruction : in std_logic_vector(31 downto 0);
        instruction_valid : in std_logic;
        pc : in unsigned(31 downto 0);
        invalid_instruction : out std_logic;

        decoded_uop : out T_uop
    );
end instruction_decoder;

architecture rtl of instruction_decoder is
    type T_instruction_type is (R_TYPE, I_TYPE, S_TYPE, B_TYPE, U_TYPE, J_TYPE);
    signal instruction_type : T_instruction_type;

    signal funct3 : std_logic_vector(2 downto 0);
    signal funct7 : std_logic_vector(6 downto 0);

    signal exec_unit_id : unsigned(EXEC_UNIT_ID_WIDTH - 1 downto 0);
    signal immediate : std_logic_vector(31 downto 0);
    signal funct : std_logic_vector(9 downto 0);
begin
    funct3 <= instruction(14 downto 12);
    funct7 <= instruction(31 downto 25);

    -- See table 70. in Chapter 34. of RISC-V unprivileged spec
    -- for decoding table
    P_decode_type : process(instruction, instruction_valid, funct3, funct7)
    begin
        invalid_instruction <= '0';
        if instruction(1 downto 0) /= "11" then
            invalid_instruction <= instruction_valid;
        else
            funct <= funct7 & funct3; 
            case instruction(6 downto 2) is
            when OPCODE_LOAD =>
                instruction_type <= I_TYPE;
                exec_unit_id <= to_unsigned(1, EXEC_UNIT_ID_WIDTH);
                funct <= "0000000" & funct3;
            when OPCODE_STORE =>
                instruction_type <= S_TYPE;
                exec_unit_id <= to_unsigned(1, EXEC_UNIT_ID_WIDTH);
                funct <= "0000001" & funct3;
            when OPCODE_BRANCH =>
                instruction_type <= B_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
            when OPCODE_OP =>
                instruction_type <= R_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
                funct <= "000000" & funct7(6) & funct3;
            when OPCODE_OP_IMM =>
                instruction_type <= I_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
                if funct3 = "001" or funct3 = "101" then
                    funct <= "100000" & funct7(6) & funct3;
                else
                    funct <= "1000000" & funct3;
                end if;
            when OPCODE_AUIPC =>
                instruction_type <= U_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
            when OPCODE_LUI =>
                instruction_type <= U_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
            when OPCODE_JAL =>
                instruction_type <= J_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
            when OPCODE_JALR =>
                instruction_type <= I_TYPE;
                exec_unit_id <= to_unsigned(0, EXEC_UNIT_ID_WIDTH);
            when others =>
                invalid_instruction <= instruction_valid;
            end case;
        end if;
    end process;

    P_decode_immediate : process(instruction, instruction_type)
    begin
        case instruction_type is
        when R_TYPE =>
            immediate <= (others => '0');
        when I_TYPE =>
            -- Decode sign
            immediate(31 downto 11) <= (others => instruction(31));
            -- Decode rest
            immediate(10 downto 0) <= instruction(30 downto 20);
        when S_TYPE =>
            -- Decode sign
            immediate(31 downto 11) <= (others => instruction(31));
            -- Decode rest
            immediate(10 downto 5) <= instruction(30 downto 25);
            immediate(4 downto 0) <= instruction(11 downto 7);
        when B_TYPE =>
            -- Decode sign
            immediate(31 downto 12) <= (others => instruction(31));
            -- Decode rest
            immediate(11) <= instruction(7);
            immediate(10 downto 5) <= instruction(30 downto 25);
            immediate(4 downto 1) <= instruction(11 downto 8);
            immediate(0) <= '0';
        when U_TYPE =>
            immediate(31 downto 12) <= instruction(31 downto 12);
            immediate(11 downto 0) <= (others => '0');
        when J_TYPE =>
            -- Decode sign
            immediate(31 downto 20) <= (others => instruction(31));
            -- Decode rest
            immediate(19 downto 12) <= instruction(19 downto 12);
            immediate(11) <= instruction(20);
            immediate(10 downto 1) <= instruction(30 downto 21);
            immediate(0) <= '0';
        when others =>
            immediate <= (others => '0');
        end case;
    end process;

    decoded_uop.pc <= pc;
    decoded_uop.exec_unit_id <= exec_unit_id;
    decoded_uop.funct <= funct;
    decoded_uop.arch_src_reg_1 <= instruction(19 downto 15);
    decoded_uop.arch_src_reg_2 <= instruction(24 downto 20);
    decoded_uop.arch_dst_reg <= instruction(11 downto 7);
    decoded_uop.immediate <= immediate;
    decoded_uop.valid <= instruction_valid;
end rtl;
