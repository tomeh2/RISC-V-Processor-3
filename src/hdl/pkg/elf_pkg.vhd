library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use STD.TEXTIO.ALL;

package elf_pkg is
    constant console_prefix : string := "[ELF_PARSER]: ";
    type T_char_file is file of character;
    type T_byte_array is array(natural range<>) of std_logic_vector(7 downto 0);
        
    type T_elf_header is record
        e_format : std_logic_vector(7 downto 0);
        e_endianness : std_logic_vector(7 downto 0);
        e_version_1 : std_logic_vector(7 downto 0);
        e_abi : std_logic_vector(7 downto 0);
        e_abi_version : std_logic_vector(7 downto 0);
        e_type : std_logic_vector(15 downto 0);
        e_machine : std_logic_vector(15 downto 0);
        e_version_2 : std_logic_vector(31 downto 0);
        e_entry : std_logic_vector(31 downto 0);
        e_phoff : std_logic_vector(31 downto 0);
        e_shoff : std_logic_vector(31 downto 0);
        e_flags : std_logic_vector(31 downto 0);
        e_ehsize : std_logic_vector(15 downto 0);
        e_phentsize : std_logic_vector(15 downto 0);
        e_phnum : std_logic_vector(15 downto 0);
        e_shentsize : std_logic_vector(15 downto 0);
        e_shnum : std_logic_vector(15 downto 0);
        e_shstrndx : std_logic_vector(15 downto 0);
    end record;
    
    type T_elf_prog_header is record
        p_type : std_logic_vector(31 downto 0);
        p_flags_1 : std_logic_vector(31 downto 0);
        p_offset : std_logic_vector(31 downto 0);
        p_vaddr : std_logic_vector(31 downto 0);
        p_paddr : std_logic_vector(31 downto 0);
        p_filesz : std_logic_vector(31 downto 0);
        p_memsz : std_logic_vector(31 downto 0);
        p_flags_2 : std_logic_vector(31 downto 0);
        p_align : std_logic_vector(31 downto 0);
    end record;
    type T_prog_headers is array (0 to 7) of T_elf_prog_header;
    
    type T_elf_sect_header is record
        sh_name : std_logic_vector(31 downto 0);
        sh_type : std_logic_vector(31 downto 0);
        sh_flags : std_logic_vector(31 downto 0);
        sh_addr : std_logic_vector(31 downto 0);
        sh_offset : std_logic_vector(31 downto 0);
        sh_size : std_logic_vector(31 downto 0);
        sh_link : std_logic_vector(31 downto 0);
        sh_info : std_logic_vector(31 downto 0);
        sh_addralign : std_logic_vector(31 downto 0);
        sh_entsize : std_logic_vector(31 downto 0);
    end record;
    type T_sect_headers is array (0 to 7) of T_elf_sect_header;
    
    type T_elf_file is record
        filename : string(1 to 64);
        elf_header : T_elf_header;
        prog_headers : T_prog_headers;
        sect_headers : T_sect_headers;
    end record;

    procedure F_seek(variable fp : T_char_file;
                     variable elf_struct : in T_elf_file; 
                     constant offset : natural);
    procedure F_print_elf_struct(variable elf_struct : in T_elf_file);
    procedure F_read_elf_chk_magic(variable fp : T_char_file; variable status : inout integer);
    procedure F_read_elf(constant filename : string; variable elf_struct : inout T_elf_file);
    procedure F_read_elf_header(variable fp : T_char_file;
                                variable elf_struct : inout T_elf_file);
    procedure F_read_program_header(variable fp : T_char_file;
                                    variable prog_header_struct : inout T_elf_prog_header);
    procedure F_read_section_header(variable fp : T_char_file;
                                    variable sect_header_struct : inout T_elf_sect_header);
    procedure F_construct_memory_image(variable elf_struct : in T_elf_file;
                                       variable mem_image : out T_byte_array);
    procedure F_read_bytes(variable fp : T_char_file; 
                           constant num_bytes : natural;
                           variable vect : inout std_logic_vector;
                           constant endianness : natural range 0 to 1 := 1);
end package;

package body elf_pkg is
    procedure F_seek(variable fp : T_char_file;
                     variable elf_struct : in T_elf_file; 
                     constant offset : natural) is
        variable ch_buffer : character;
    begin
        file_close(fp);
        file_open(fp, elf_struct.filename, read_mode);
        
        for i in 0 to offset - 1 loop
            read(fp, ch_buffer);
        end loop;
    end procedure;

    procedure F_print_elf_struct(variable elf_struct : in T_elf_file) is
    begin
        report "----- ELF HEADER -----";
        
        if elf_struct.elf_header.e_format = X"01" then
            report console_prefix & "Format: " & "32-bit";
        elsif elf_struct.elf_header.e_format = X"02" then
            report console_prefix & "Format: " & "64-bit";
        else
            report console_prefix & "Format: " & "Unknown";
        end if;

        if elf_struct.elf_header.e_endianness = X"01" then
            report console_prefix & "Endianness: " & "Little-endian";
        elsif elf_struct.elf_header.e_endianness = X"02" then
            report console_prefix & "Endianness: " & "Big_endian";
        else
            report console_prefix & "Endianness: " & "Unknown";
        end if;
        
        report console_prefix & "Version 1: " & "0x" & to_hex_string(elf_struct.elf_header.e_version_1);
        
        if elf_struct.elf_header.e_abi = X"00" then
            report console_prefix & "ABI: " & "System V";
        else
            report console_prefix & "ABI: " & "Other";
        end if;
        
        report console_prefix & "ABI Version: " & "0x" & to_hex_string(elf_struct.elf_header.e_abi_version);
        
        if elf_struct.elf_header.e_type = X"0000" then
            report console_prefix & "Type: " & "None";
        elsif elf_struct.elf_header.e_type = X"0001" then
            report console_prefix & "Type: " & "Relocatable file";
        elsif elf_struct.elf_header.e_type = X"0002" then
            report console_prefix & "Type: " & "Executable file";
        elsif elf_struct.elf_header.e_type = X"0003" then
            report console_prefix & "Type: " & "Shared object";
        elsif elf_struct.elf_header.e_type = X"0004" then
            report console_prefix & "Type: " & "Core file";
        else
            report console_prefix & "Type: " & "Unknown";
        end if;
        
        if elf_struct.elf_header.e_machine = X"0000" then
            report console_prefix & "ISA: " & "Unspecific";
        elsif elf_struct.elf_header.e_machine = X"00F3" then
            report console_prefix & "ISA: " & "RISC-V";
        else
            report console_prefix & "ISA: " & "Other";
        end if;
        
        report console_prefix & "Version 2: " & "0x" & to_hex_string(elf_struct.elf_header.e_version_2);
        report console_prefix & "Entry: " & "0x" & to_hex_string(elf_struct.elf_header.e_entry);
        report console_prefix & "Program Header Table Offset: " & "0x" & to_hex_string(elf_struct.elf_header.e_phoff);
        report console_prefix & "Section Header Table Offset: " & "0x" & to_hex_string(elf_struct.elf_header.e_shoff);
        report console_prefix & "Flags: " & "0x" & to_hex_string(elf_struct.elf_header.e_flags);
        report console_prefix & "Header Size: " & "0x" & to_hex_string(elf_struct.elf_header.e_ehsize);
        report console_prefix & "Program Header Table Size: " & "0x" & to_hex_string(elf_struct.elf_header.e_phentsize);
        report console_prefix & "Program Header Entries: " & "0x" & to_hex_string(elf_struct.elf_header.e_phnum);
        report console_prefix & "Section Header Size: " & "0x" & to_hex_string(elf_struct.elf_header.e_shentsize);
        report console_prefix & "Section Header Table Entries: " & "0x" & to_hex_string(elf_struct.elf_header.e_shnum);
        report console_prefix & "Index Of Section Name Entry: " & "0x" & to_hex_string(elf_struct.elf_header.e_shstrndx);
        
        report "===== PROGRAM HEADERS =====";
        
        for i in 0 to to_integer(unsigned(elf_struct.elf_header.e_phnum)) - 1 loop
            report "----- PROGRAM HEADER " & integer'image(i) & " -----";
            if elf_struct.prog_headers(i).p_type = X"00000000" then
                report console_prefix & "Segment Type: " & "None";
            elsif elf_struct.prog_headers(i).p_type = X"00000001" then
                report console_prefix & "Segment Type: " & "Loadable Segment";
            elsif elf_struct.prog_headers(i).p_type = X"00000002" then
                report console_prefix & "Segment Type: " & "Dynamic Linking Info";
            elsif elf_struct.prog_headers(i).p_type = X"00000003" then
                report console_prefix & "Segment Type: " & "Interpreter Info";
            elsif elf_struct.prog_headers(i).p_type = X"00000004" then
                report console_prefix & "Segment Type: " & "Aux Info";
            elsif elf_struct.prog_headers(i).p_type = X"00000005" then
                report console_prefix & "Segment Type: " & "Reserved";
            elsif elf_struct.prog_headers(i).p_type = X"00000006" then
                report console_prefix & "Segment Type: " & "Program Header Table";
            elsif elf_struct.prog_headers(i).p_type = X"00000007" then
                report console_prefix & "Segment Type: " & "Thread-Local Storage Template";
            else
                report console_prefix & "Segment Type: " & "Other " & to_hex_string(elf_struct.prog_headers(i).p_type);
            end if;
            
            if elf_struct.prog_headers(i).p_flags_1 = X"00000001" then
                report console_prefix & "Flags 1: " & "Executable Segment";
            elsif elf_struct.prog_headers(i).p_flags_1 = X"00000002" then
                report console_prefix & "Flags 1: " & "Writeable Segment";
            elsif elf_struct.prog_headers(i).p_flags_1 = X"00000004" then
                report console_prefix & "Flags 1: " & "Readable Segment";
            else
                report console_prefix & "Flags 1: " & "Other";
            end if;
            
            report console_prefix & "Segment Offset: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_offset);
            report console_prefix & "Virtual Address: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_vaddr);
            report console_prefix & "Physical Address: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_paddr);
            report console_prefix & "Segment Size: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_filesz);
            report console_prefix & "Size In Memory: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_memsz);
            report console_prefix & "Flags 2: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_flags_2);
            report console_prefix & "Alignment: " & "0x" & to_hex_string(elf_struct.prog_headers(i).p_align);
        end loop;
        
        report "===== SECTION HEADERS =====";
        
        for i in 0 to to_integer(unsigned(elf_struct.elf_header.e_shnum)) - 1 loop
            report "----- SECTION HEADER " & integer'image(i) & " -----";
            if elf_struct.sect_headers(i).sh_type = X"0000_0000" then
                report console_prefix & "Section Type: " & "Unused";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0001" then
                report console_prefix & "Section Type: " & "Program Data";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0002" then
                report console_prefix & "Section Type: " & "Symbol Table";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0003" then
                report console_prefix & "Section Type: " & "String Table";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0004" then
                report console_prefix & "Section Type: " & "Relocation entries \w addends";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0005" then
                report console_prefix & "Section Type: " & "Symbol Hash Table";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0006" then
                report console_prefix & "Section Type: " & "Dynamic Linking Info";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0007" then
                report console_prefix & "Section Type: " & "Notes";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0008" then
                report console_prefix & "Section Type: " & "BSS";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0009" then
                report console_prefix & "Section Type: " & "Relocation entries \wo addends";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_000A" then
                report console_prefix & "Section Type: " & "Reserved";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_000B" then
                report console_prefix & "Section Type: " & "Dynamic Linker Symbol Table";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_000E" then
                report console_prefix & "Section Type: " & "Array of Constructors";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_000F" then
                report console_prefix & "Section Type: " & "Array of Destructors";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0010" then
                report console_prefix & "Section Type: " & "Array of Pre-Constructors";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0011" then
                report console_prefix & "Section Type: " & "Section Group";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0012" then
                report console_prefix & "Section Type: " & "Extended Section Indices";
            elsif elf_struct.sect_headers(i).sh_type = X"0000_0013" then
                report console_prefix & "Section Type: " & "Number of Defined Types";
            elsif elf_struct.sect_headers(i).sh_type = X"6000_0000" then
                report console_prefix & "Section Type: " & "OS-Specific";
            else
                report console_prefix & "Section Type: " & "Other";
            end if;
            
            report console_prefix & "Flags: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_flags);
            report console_prefix & "Virtual Address: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_addr);
            report console_prefix & "Offset: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_offset);
            report console_prefix & "Size: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_size);
            report console_prefix & "Link: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_link);
            report console_prefix & "Info: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_info);
            report console_prefix & "Alignment: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_addralign);
            report console_prefix & "Entry Size: " & "0x" & to_hex_string(elf_struct.sect_headers(i).sh_entsize);
        end loop;
    end procedure;
    
    procedure F_read_bytes(variable fp : T_char_file; 
                           constant num_bytes : natural;
                           variable vect : inout std_logic_vector;
                           constant endianness : natural range 0 to 1 := 1) is
        variable ch_buffer : character;
        variable ch_buffer_vec : std_logic_vector(7 downto 0);
    begin
        if endianness = 0 then
            for i in num_bytes downto 1 loop
                read(fp, ch_buffer);
                ch_buffer_vec := std_logic_vector(to_unsigned(character'pos(ch_buffer), 8));
                vect(8 * i - 1 downto 8 * (i - 1)) := ch_buffer_vec;
            end loop;
        else
            for i in 1 to num_bytes loop
                read(fp, ch_buffer);
                ch_buffer_vec := std_logic_vector(to_unsigned(character'pos(ch_buffer), 8));
                vect(8 * i - 1 downto 8 * (i - 1)) := ch_buffer_vec;
            end loop;
        end if;
    end procedure;
    
    procedure F_read_elf_chk_magic(variable fp : T_char_file; variable status : inout integer) is
        variable ch_buffer : character;
        variable magic_num : std_logic_vector(31 downto 0);
    begin
        F_read_bytes(fp, 4, magic_num, 0);
        
        if magic_num = X"7F454C46" then
            report "[ELF_PARSER]: Magic number OK";
            status := 0;
        else
            report "[ELF_PARSER]: Magic number not found";
            status := -1;
        end if;
    end procedure;
    
    procedure F_read_elf_header(variable fp : T_char_file;
                                variable elf_struct : inout T_elf_file) is
        variable ignore : std_logic_vector(127 downto 0);
    begin
        F_read_bytes(fp, 1, elf_struct.elf_header.e_format);
        F_read_bytes(fp, 1, elf_struct.elf_header.e_endianness);
        F_read_bytes(fp, 1, elf_struct.elf_header.e_version_1);
        F_read_bytes(fp, 1, elf_struct.elf_header.e_abi);
        F_read_bytes(fp, 1, elf_struct.elf_header.e_abi_version);
        F_read_bytes(fp, 7, ignore);        -- Padding
        F_read_bytes(fp, 2, elf_struct.elf_header.e_type);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_machine);
        F_read_bytes(fp, 4, elf_struct.elf_header.e_version_2);
        F_read_bytes(fp, 4, elf_struct.elf_header.e_entry);
        F_read_bytes(fp, 4, elf_struct.elf_header.e_phoff);
        F_read_bytes(fp, 4, elf_struct.elf_header.e_shoff);
        F_read_bytes(fp, 4, elf_struct.elf_header.e_flags);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_ehsize);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_phentsize);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_phnum);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_shentsize);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_shnum);
        F_read_bytes(fp, 2, elf_struct.elf_header.e_shstrndx);
    end procedure;
    
    procedure F_read_program_header(variable fp : T_char_file;
                                    variable prog_header_struct : inout T_elf_prog_header) is
    begin
        F_read_bytes(fp, 4, prog_header_struct.p_type);
        F_read_bytes(fp, 4, prog_header_struct.p_offset);
        F_read_bytes(fp, 4, prog_header_struct.p_vaddr);
        F_read_bytes(fp, 4, prog_header_struct.p_paddr);
        F_read_bytes(fp, 4, prog_header_struct.p_filesz);
        F_read_bytes(fp, 4, prog_header_struct.p_memsz);
        F_read_bytes(fp, 4, prog_header_struct.p_flags_2);
        F_read_bytes(fp, 4, prog_header_struct.p_align);
    end procedure;
    
    procedure F_read_section_header(variable fp : T_char_file;
                                    variable sect_header_struct : inout T_elf_sect_header) is
    begin
        F_read_bytes(fp, 4, sect_header_struct.sh_name);
        F_read_bytes(fp, 4, sect_header_struct.sh_type);
        F_read_bytes(fp, 4, sect_header_struct.sh_flags);
        F_read_bytes(fp, 4, sect_header_struct.sh_addr);
        F_read_bytes(fp, 4, sect_header_struct.sh_offset);
        F_read_bytes(fp, 4, sect_header_struct.sh_size);
        F_read_bytes(fp, 4, sect_header_struct.sh_link);
        F_read_bytes(fp, 4, sect_header_struct.sh_info);
        F_read_bytes(fp, 4, sect_header_struct.sh_addralign);
        F_read_bytes(fp, 4, sect_header_struct.sh_entsize);
    end procedure;

    procedure F_construct_memory_image(variable elf_struct : in T_elf_file;
                                       variable mem_image : out T_byte_array) is
        file fp : T_char_file;
        variable fos : file_open_status;
        variable mem_image_index : natural := 0;
    begin
        file_open(fp, elf_struct.filename, read_mode);
        if fos /= open_ok then
            report "[ELF_PARSER]: Failed to open ELF file" severity error;
            return;
        end if;
        
        for i in 0 to to_integer(unsigned(elf_struct.elf_header.e_shnum)) - 1 loop
            if elf_struct.sect_headers(i).sh_type = X"0000_0001" then
                F_seek(fp, elf_struct, to_integer(unsigned(elf_struct.sect_headers(i).sh_offset)));
                for j in 0 to to_integer(unsigned(elf_struct.sect_headers(i).sh_size)) - 1 loop
                    F_read_bytes(fp, 1, mem_image(mem_image_index));
                    mem_image_index := mem_image_index + 1;
                end loop;
            end if;
        end loop;
        file_close(fp);
    end procedure;

    procedure F_read_elf(constant filename : string; variable elf_struct : inout T_elf_file) is
        variable ret_status : integer;
        file fp : T_char_file;
        variable fos : file_open_status;
    begin
        elf_struct.filename(1 to filename'length) := filename;
        file_open(fos, fp, filename, read_mode);
        if fos /= open_ok then
            report "[ELF_PARSER]: Failed to open ELF file" severity error;
            return;
        end if;
        
        F_read_elf_chk_magic(fp, ret_status);
        if ret_status /= 0 then
            report "[ELF_PARSER]: Magic number not found" severity error;
            return;
        end if;
        
        F_read_elf_header(fp, elf_struct);
        F_seek(fp, elf_struct, to_integer(unsigned(elf_struct.elf_header.e_phoff)));
        for i in 0 to to_integer(unsigned(elf_struct.elf_header.e_phnum)) - 1 loop
            F_read_program_header(fp, elf_struct.prog_headers(i));
        end loop;
        
        F_seek(fp, elf_struct, to_integer(unsigned(elf_struct.elf_header.e_shoff)));
        for i in 0 to to_integer(unsigned(elf_struct.elf_header.e_shnum)) - 1 loop
            F_read_section_header(fp, elf_struct.sect_headers(i));
        end loop;
        
        file_close(fp);
    end procedure;
end package body;
