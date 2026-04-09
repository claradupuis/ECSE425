library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;


ENTITY processor IS

    PORT (
        clk : in std_logic;
        reset : in std_logic;
        dbg_imem_writedata   : out std_logic_vector(7 downto 0);
        dbg_imem_readdata    : out std_logic_vector(7 downto 0);
        dbg_imem_address     : out integer range 0 to 32767;
        dbg_imem_memwrite    : out std_logic;
        dbg_imem_memread     : out std_logic;
        dbg_imem_waitrequest : out std_logic;
        dbg_dmem_writedata   : out std_logic_vector(7 downto 0);
        dbg_dmem_readdata    : out std_logic_vector(7 downto 0);
        dbg_dmem_address     : out integer range 0 to 32767;
        dbg_dmem_memwrite    : out std_logic;
        dbg_dmem_waitrequest : out std_logic;
        dbg_dmem_memread     : out std_logic;
        dbg_reg_file : out reg_array_t
    );
end entity;

ARCHITECTURE behaviour of processor is
    -- memory (instr + data)
    COMPONENT memory IS
        GENERIC(
            ram_size : INTEGER := 32768;
            mem_delay : time := 10 ns;
            clock_period : time := 1 ns
        );
        PORT (
            clock: IN STD_LOGIC;
            writedata: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
            address: IN INTEGER RANGE 0 TO ram_size-1;
            memwrite: IN STD_LOGIC;
            memread: IN STD_LOGIC;
            readdata: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            waitrequest: OUT STD_LOGIC
        );
    end COMPONENT;

    -- registers
    -- type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
    signal reg_file : reg_array_t := (others => (others => '0')); --sets all to 0 i think

    --pc
    signal pc : STD_LOGIC_VECTOR(31 downto 0);

    -- instruction memory 
    signal imem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal imem_readdata    : std_logic_vector(7 downto 0);
    signal imem_address     : integer range 0 to 32767 := 0;
    signal imem_memwrite    : std_logic := '0';
    signal imem_memread     : std_logic := '0';
    signal imem_waitrequest : std_logic;

    -- data memory
    signal dmem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal dmem_readdata    : std_logic_vector(7 downto 0);
    signal dmem_address     : integer range 0 to 32767 := 0;
    signal dmem_memwrite    : std_logic := '0';
    signal dmem_memread     : std_logic := '0';
    signal dmem_waitrequest : std_logic;

    --Instruction fetch
    signal instr_if : std_logic_vector(31 downto 0) := (others => '0');

    --IF/ID pipeline
    signal if_id_pc    : std_logic_vector(31 downto 0) := (others => '0');
    signal if_id_instr : std_logic_vector(31 downto 0) := (others => '0');
    
    -- Decode 
    signal id_rs1      : integer range 0 to 31;
    signal id_rs2      : integer range 0 to 31;
    signal id_rd       : integer range 0 to 31;
    signal id_opcode   : std_logic_vector(6 downto 0);
    signal id_funct3   : std_logic_vector(2 downto 0);
    signal id_funct7   : std_logic_vector(6 downto 0);
    signal id_reg1     : std_logic_vector(31 downto 0);
    signal id_reg2     : std_logic_vector(31 downto 0);
    signal id_imm      : std_logic_vector(31 downto 0);

    signal id_regwrite : std_logic;
    signal id_memread  : std_logic;
    signal id_memwrite : std_logic;
    signal id_memtoreg : std_logic;
    signal id_alu_use_imm   : std_logic;
    signal id_branch   : std_logic;
    signal id_jump     : std_logic;
    signal id_aluop    : std_logic_vector(3 downto 0);

    -- ID/EX pipeline
    signal id_ex_pc       : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_instr    : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_reg1     : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_reg2     : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_imm      : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_rs1      : integer range 0 to 31 := 0;
    signal id_ex_rs2      : integer range 0 to 31 := 0;
    signal id_ex_rd       : integer range 0 to 31 := 0;
    signal id_ex_funct3   : std_logic_vector(2 downto 0) := (others => '0');
    signal id_ex_funct7   : std_logic_vector(6 downto 0) := (others => '0');

    signal id_ex_regwrite : std_logic := '0';
    signal id_ex_memread  : std_logic := '0';
    signal id_ex_memwrite : std_logic := '0';
    signal id_ex_memtoreg : std_logic := '0';
    signal id_ex_alu_use_imm   : std_logic := '0';
    signal id_ex_branch   : std_logic := '0';
    signal id_ex_jump     : std_logic := '0';

   -- Execute
    signal ex_alu_in2      : std_logic_vector(31 downto 0);
    signal ex_alu_result   : std_logic_vector(31 downto 0);
    signal ex_branch_taken : std_logic;
    signal ex_branch_addr  : std_logic_vector(31 downto 0);
    signal ex_link_addr    : std_logic_vector(31 downto 0) := (others => '0');

   -- EX/Mem pipeline
    signal ex_mem_instr    : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_alu      : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_reg2     : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_rd       : integer range 0 to 31 := 0;
    signal ex_mem_funct3   : std_logic_vector(2 downto 0) := (others => '0');
    signal ex_mem_regwrite : std_logic := '0';
    signal ex_mem_memread  : std_logic := '0';
    signal ex_mem_memwrite : std_logic := '0';
    signal ex_mem_memtoreg : std_logic := '0';
    signal ex_mem_branch_taken : std_logic := '0';

    --Memory
    signal mem_load_data   : std_logic_vector(31 downto 0) := (others => '0');

    --Memory/Writeback pipeline
    signal mem_wb_instr    : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_alu      : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_mem      : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_rd       : integer range 0 to 31 := 0;
    signal mem_wb_regwrite : std_logic := '0';
    signal mem_wb_memtoreg : std_logic := '0';

    --writeback
    signal wb_data         : std_logic_vector(31 downto 0);

    function sign_extend(inp : std_logic_vector; out_size : integer) return std_logic_vector is
    variable result : std_logic_vector(out_size-1 downto 0);
    begin
        result := (others => inp(inp'left));
        result(inp'length-1 downto 0) := inp;
        return result;
    end function;
    

begin
    instruction_mem : entity work.memory
        generic map (
            ram_size     => 32768,
            mem_delay    => 10 ns,
            clock_period => 1 ns
        )
        port map (
            clock       => clk,
            writedata   => imem_writedata,
            address     => imem_address,
            memwrite    => imem_memwrite,
            memread     => imem_memread,
            readdata    => imem_readdata,
            waitrequest => imem_waitrequest
        );

    data_mem : entity work.memory
        generic map (
            ram_size     => 32768,
            mem_delay    => 10 ns,
            clock_period => 1 ns
        )
        port map (
            clock       => clk,
            writedata   => dmem_writedata,
            address     => dmem_address,
            memwrite    => dmem_memwrite,
            memread     => dmem_memread,
            readdata    => dmem_readdata,
            waitrequest => dmem_waitrequest
        );

    
    id_opcode <= if_id_instr(6 downto 0);
    id_rd     <= to_integer(unsigned(if_id_instr(11 downto 7)));
    id_funct3 <= if_id_instr(14 downto 12);
    id_rs1    <= to_integer(unsigned(if_id_instr(19 downto 15)));
    id_rs2    <= to_integer(unsigned(if_id_instr(24 downto 20)));
    id_funct7 <= if_id_instr(31 downto 25);

    id_reg1 <= reg_file(id_rs1); -- used later in EX stage for operations
    id_reg2 <= reg_file(id_rs2);
    
    reg_file(0) <= (others => '0');

    -- connect debug ports to signals
    dbg_imem_writedata <= imem_writedata;
    dbg_imem_readdata   <= imem_readdata;
    dbg_imem_address <= imem_address;  
    dbg_imem_memwrite <= imem_memwrite;
    dbg_imem_memread <= imem_memread;
    dbg_imem_waitrequest <= imem_waitrequest;
    dbg_dmem_writedata <= dmem_writedata;
    dbg_dmem_readdata <= dmem_readdata;
    dbg_dmem_address  <= dmem_address;
    dbg_dmem_memwrite    <= dmem_memwrite;
    dbg_dmem_memread     <= dmem_memread;
    dbg_dmem_waitrequest <= dmem_waitrequest;


    process(if_id_instr, id_opcode)
    begin
        case id_opcode is
            -- I-type
            when "0010011" | "0000011" | "1100111" =>
                id_imm <= sign_extend(if_id_instr(31 downto 20), 32);

            -- S-type
            when "0100011" =>
                id_imm <= sign_extend(if_id_instr(31 downto 25) & if_id_instr(11 downto 7), 32);

            -- B-type
            when "1100011" =>
                id_imm <= sign_extend(
                    if_id_instr(31) &
                    if_id_instr(7) &
                    if_id_instr(30 downto 25) &
                    if_id_instr(11 downto 8) &
                    '0', 32);

            -- U-type
            when "0110111" | "0010111" =>
                id_imm <= if_id_instr(31 downto 12) & x"000";

            -- J-type
            when "1101111" =>
                id_imm <= sign_extend(
                    if_id_instr(31) &
                    if_id_instr(19 downto 12) &
                    if_id_instr(20) &
                    if_id_instr(30 downto 21) &
                    '0', 32);

            when others =>
                id_imm <= (others => '0');
        end case;
    end process;

    -- when the opcode changes, the processor needs to decide what it will do 
    process(id_opcode, id_funct3, id_funct7)
    begin
        id_regwrite <= '0';
        id_memread  <= '0';
        id_memwrite <= '0';
        id_memtoreg <= '0';
        id_alu_use_imm   <= '0';
        id_branch   <= '0';
        id_jump     <= '0';

        case id_opcode is
            -- R-type --> Write a result and use two registers 
            when "0110011" =>
                id_regwrite <= '1';
                id_alu_use_imm   <= '0';

            -- I-type --> writes and uses immediate value
            when "0010011" =>
                id_regwrite <= '1';
                id_alu_use_imm   <= '1';

            -- lw --> read memory, write result to register 
            when "0000011" =>
                id_regwrite <= '1';
                id_memread  <= '1';
                id_memtoreg <= '1';
                id_alu_use_imm   <= '1';

            -- store (sw) -- write to memory (not register)
            when "0100011" =>
                id_memwrite <= '1';
                id_regwrite <= '0';
                id_alu_use_imm   <= '1';

            -- Branches
            when "1100011" =>
                id_branch <= '1';

            -- jal -- Pc+4
            when "1101111" =>
                id_regwrite <= '1';
                id_jump     <= '1';

            -- jalr --> jumps to imm
            when "1100111" =>
                id_regwrite <= '1';
                id_jump     <= '1';
                id_alu_use_imm   <= '1';

            -- lui --> load imm value in register
            when "0110111" =>
                id_regwrite <= '1';
                id_alu_use_imm   <= '1';

            -- auipc --> rd = Pc+imm
            when "0010111" =>
                id_regwrite <= '1';
                id_alu_use_imm   <= '1';

            when others =>
                null;
        end case;
    end process;

    --choose the ALU input (register or imm)
    ex_alu_in2 <= id_ex_reg2 when id_ex_alu_use_imm = '0' else id_ex_imm;



    --EXE stage
    process(id_ex_reg1, id_ex_reg2, ex_alu_in2, id_ex_instr, id_ex_funct3, id_ex_funct7, id_ex_pc, id_ex_imm)
        variable shift_amount : integer range 0 to 31;
    begin
        ex_alu_result   <= (others => '0');
        ex_branch_taken <= '0';
        ex_branch_addr  <= (others => '0');

        --Pc = Pc+4 --> for jal and jalr
        ex_link_addr    <= std_logic_vector(unsigned(id_ex_pc) + 4);

        shift_amount := to_integer(unsigned(ex_alu_in2(4 downto 0)));

        case id_ex_instr(6 downto 0) is
            -- R-type
            when "0110011" =>
                case id_ex_funct3 is
                    when "000" =>
                        if id_ex_funct7 = "0000000" then
                            --add
                            ex_alu_result <= std_logic_vector(signed(id_ex_reg1) + signed(ex_alu_in2)); 

                        elsif id_ex_funct7 = "0100000" then
                            --sub
                            ex_alu_result <= std_logic_vector(signed(id_ex_reg1) - signed(ex_alu_in2));

                        elsif id_ex_funct7 = "0000001" then
                            --mul REVIEEEEEEWWW THISSSSSS
                            ex_alu_result <= std_logic_vector(signed(id_ex_reg1) * signed(ex_alu_in2)); 

                        end if;
                    
                        when "110" =>
                        --or
                        ex_alu_result <= id_ex_reg1 or ex_alu_in2; 

                    when "111" =>
                        -- and
                        ex_alu_result <= id_ex_reg1 and ex_alu_in2;

                    when "001" =>
                        --sll
                        ex_alu_result <= std_logic_vector(shift_left(unsigned(id_ex_reg1), shift_amount)); 

                    when "101" =>
                        if id_ex_funct7 = "0000000" then
                            --srl
                            ex_alu_result <= std_logic_vector(shift_right(unsigned(id_ex_reg1), shift_amount)); 
                        elsif id_ex_funct7 = "0100000" then
                            -- sra
                            ex_alu_result <= std_logic_vector(shift_right(signed(id_ex_reg1), shift_amount)); 
                        end if;

                    when others =>
                        null;
                end case;

            -- I-type ALU
            when "0010011" =>
                case id_ex_funct3 is
                    when "000" =>
                        --addi
                        ex_alu_result <= std_logic_vector(signed(id_ex_reg1) + signed(ex_alu_in2)); 

                    when "100" =>
                        --xori
                        ex_alu_result <= id_ex_reg1 xor ex_alu_in2; 

                    when "110" =>
                        --ori
                        ex_alu_result <= id_ex_reg1 or ex_alu_in2;

                    when "111" =>
                        -- andi
                        ex_alu_result <= id_ex_reg1 and ex_alu_in2; 

                    when "010" =>
                        --slti
                        if signed(id_ex_reg1) < signed(ex_alu_in2) then
                            ex_alu_result <= x"00000001";
                        else
                            ex_alu_result <= x"00000000";
                        end if; 

                    when others =>
                        null;
                end case;

            -- load or store
            when "0000011" | "0100011" =>
                ex_alu_result <= std_logic_vector(signed(id_ex_reg1) + signed(id_ex_imm));

            -- B
            when "1100011" =>
                ex_branch_addr <= std_logic_vector(unsigned(id_ex_pc) + unsigned(id_ex_imm));

                case id_ex_funct3 is
                    when "000" =>
                        --beq
                        if id_ex_reg1 = id_ex_reg2 then ex_branch_taken <= '1'; end if; 

                    when "001" =>
                        --bne
                        if id_ex_reg1 /= id_ex_reg2 then ex_branch_taken <= '1'; end if; 

                    when "100" =>
                        --blt
                        if signed(id_ex_reg1) < signed(id_ex_reg2) then ex_branch_taken <= '1'; end if; 

                    when "101" =>
                        --bge
                        if signed(id_ex_reg1) >= signed(id_ex_reg2) then ex_branch_taken <= '1'; end if;

                    when others =>
                        null;
                end case;

            -- jump and link
            when "1101111" =>
                --jal
                ex_alu_result   <= ex_link_addr; --Pc+4
                ex_branch_addr  <= std_logic_vector(unsigned(id_ex_pc) + unsigned(id_ex_imm));
                ex_branch_taken <= '1';

            -- jump and link register
            when "1100111" =>
                --jalr 
                ex_alu_result   <= ex_link_addr; -- Pc+4
                ex_branch_addr  <= std_logic_vector((unsigned(id_ex_reg1) + unsigned(id_ex_imm)));
                ex_branch_taken <= '1';

            -- load upper imm
            when "0110111" =>
                --lui
                ex_alu_result <= id_ex_imm;

            -- add uper imm to pc
            when "0010111" =>
                --auipc
                ex_alu_result <= std_logic_vector(unsigned(id_ex_pc) + unsigned(id_ex_imm));

            when others =>
                null;
        end case;
    end process;

   
    wb_data <= mem_wb_mem when mem_wb_memtoreg = '1' else mem_wb_alu;



end architecture;
