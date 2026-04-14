library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.types.all;


ENTITY processor IS

    PORT (
        clk : in std_logic;
        reset : in std_logic;
        dbg_imem_writedata   : out std_logic_vector(31 downto 0);
        dbg_imem_readdata    : out std_logic_vector(31 downto 0);
        dbg_imem_address     : out integer range 0 to 32767;
        dbg_imem_memwrite    : out std_logic;
        dbg_imem_memread     : out std_logic;
        dbg_imem_waitrequest : out std_logic;
        dbg_dmem_writedata   : out std_logic_vector(31 downto 0);
        dbg_dmem_readdata    : out std_logic_vector(31 downto 0);
        dbg_dmem_address     : out integer range 0 to 32767;
        dbg_dmem_memwrite    : out std_logic;
        dbg_dmem_waitrequest : out std_logic;
        dbg_dmem_memread     : out std_logic;
        dbg_reg_file : out reg_array_t;
        -- Instruction memory loader (driven by testbench to load program)
        ld_imem_addr  : in integer range 0 to 8191;
        ld_imem_data  : in std_logic_vector(31 downto 0);
        ld_imem_write : in std_logic
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
            writedata: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
            address: IN INTEGER RANGE 0 TO (ram_size/4)-1;
            memwrite: IN STD_LOGIC;
            memread: IN STD_LOGIC;
            readdata: OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
            waitrequest: OUT STD_LOGIC
        );
    end COMPONENT;

    -- registers
    -- type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
    -- type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
    type mem_word_array_t is array (0 to 8191) of std_logic_vector(31 downto 0);
    signal reg_file : reg_array_t := (others => (others => '0')); --sets all to 0 i think

    --pc
    signal pc : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal pc_next  : std_logic_vector(31 downto 0) := (others => '0');
    signal instr_if : std_logic_vector(31 downto 0) := (others => '0');


    -- instruction memory
    signal imem_writedata : std_logic_vector(31 downto 0);
    signal imem_readdata : std_logic_vector(31 downto 0);
    signal imem_address : integer range 0 to 8191 := 0;
    signal imem_memwrite : std_logic := '0';
    signal imem_memread : std_logic := '0';
    signal imem_waitrequest : std_logic;

    -- data memory
    signal dmem_writedata : std_logic_vector(31 downto 0) := (others => '0');
    signal dmem_readdata : std_logic_vector(31 downto 0);
    signal dmem_address : integer range 0 to 8191 := 0;
    signal dmem_memwrite : std_logic := '0';
    signal dmem_memread : std_logic := '0';
    signal dmem_waitrequest : std_logic;



    --IF/ID pipeline
    signal if_id_pc : std_logic_vector(31 downto 0) := (others => '0');
    signal if_id_instr : std_logic_vector(31 downto 0) := (others => '0');

    -- Decode
    signal id_rs1 : integer range 0 to 31;
    signal id_rs2 : integer range 0 to 31;
    signal id_rd : integer range 0 to 31;
    signal id_opcode : std_logic_vector(6 downto 0);
    signal id_funct3 : std_logic_vector(2 downto 0);
    signal id_funct7 : std_logic_vector(6 downto 0);
    signal id_reg1: std_logic_vector(31 downto 0);
    signal id_reg2: std_logic_vector(31 downto 0);
    signal id_imm : std_logic_vector(31 downto 0);

    signal id_regwrite : std_logic;
    signal id_memread : std_logic;
    signal id_memwrite : std_logic;
    signal id_memtoreg : std_logic;
    signal id_alu_use_imm : std_logic;
    signal id_branch : std_logic;
    signal id_jump : std_logic;
    signal id_aluop : std_logic_vector(3 downto 0);

    -- ID/EX pipeline
    signal id_ex_pc : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_instr : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_reg1 : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_reg2 : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_imm : std_logic_vector(31 downto 0) := (others => '0');
    signal id_ex_rs1 : integer range 0 to 31 := 0;
    signal id_ex_rs2 : integer range 0 to 31 := 0;
    signal id_ex_rd : integer range 0 to 31 := 0;
    signal id_ex_funct3 : std_logic_vector(2 downto 0) := (others => '0');
    signal id_ex_funct7 : std_logic_vector(6 downto 0) := (others => '0');

    signal id_ex_regwrite : std_logic := '0';
    signal id_ex_memread : std_logic := '0';
    signal id_ex_memwrite : std_logic := '0';
    signal id_ex_memtoreg : std_logic := '0';
    signal id_ex_alu_use_imm : std_logic := '0';
    signal id_ex_branch : std_logic := '0';
    signal id_ex_jump : std_logic := '0';

   -- Execute
    signal ex_alu_in2 : std_logic_vector(31 downto 0);
    signal ex_alu_result : std_logic_vector(31 downto 0);
    signal ex_branch_taken : std_logic;
    signal ex_branch_addr : std_logic_vector(31 downto 0);
    signal ex_link_addr : std_logic_vector(31 downto 0) := (others => '0');

   -- EX/Mem pipeline
    signal debug_ex_mem_pc: std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_instr : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_alu : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_reg2 : std_logic_vector(31 downto 0) := (others => '0');
    signal ex_mem_rd : integer range 0 to 31 := 0;
    signal ex_mem_funct3 : std_logic_vector(2 downto 0) := (others => '0');
    signal ex_mem_regwrite : std_logic := '0';
    signal ex_mem_memread : std_logic := '0';
    signal ex_mem_memwrite : std_logic := '0';
    signal ex_mem_memtoreg : std_logic := '0';
    signal ex_mem_branch_taken: std_logic := '0';
    signal ex_mem_branch_addr  : std_logic_vector(31 downto 0) := (others => '0');

    --Memory
    signal mem_load_data : std_logic_vector(31 downto 0) := (others => '0');

    --Memory/Writeback pipeline
    signal mem_wb_instr : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_alu : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_mem : std_logic_vector(31 downto 0) := (others => '0');
    signal mem_wb_rd : integer range 0 to 31 := 0;
    signal mem_wb_regwrite : std_logic := '0';
    signal mem_wb_memtoreg : std_logic := '0';

    --writeback
    signal wb_data : std_logic_vector(31 downto 0);

    --stall detection
    signal currently_stalled: std_logic := '0';
    signal stalled_instr: std_logic_vector(31 downto 0) := (others => '0');
    signal stalled_pc: std_logic_vector(31 downto 0) := (others => '0');

    function sign_extend(inp : std_logic_vector; out_size:integer) return std_logic_vector is
    variable result : std_logic_vector(out_size-1 downto 0);
    begin
        result := (others => inp(inp'left));
        result(inp'length-1 downto 0) := inp;
        return result;
    end function;

    function zero_extend(inp:std_logic_vector; out_size:integer) return std_logic_vector is
    variable result:std_logic_vector(out_size-1 downto 0);
    begin
        result := (others => '0');
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

    imem_address  <= ld_imem_addr  when ld_imem_write = '1' else to_integer(unsigned(pc(14 downto 2)));
    imem_memread  <= '0'           when ld_imem_write = '1' else '1';
    imem_memwrite <= ld_imem_write;
    imem_writedata <= ld_imem_data when ld_imem_write = '1' else (others => '0');

    instr_if <= imem_readdata;
    pc_next <= ex_mem_branch_addr when ex_mem_branch_taken = '1'
        else pc when currently_stalled = '1'
        else std_logic_vector(unsigned(pc) + 4);

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                pc       <= (others => '0');
                if_id_pc    <= (others => '0');
                if_id_instr <= (others => '0');
            elsif ex_mem_branch_taken = '1' then
                pc       <= ex_mem_branch_addr;
                if_id_pc    <= (others => '0');
                if_id_instr <= x"00000013";
            elsif currently_stalled = '1' then
                 pc <= pc;
                 if_id_pc<= if_id_pc;
                 if_id_instr <= if_id_instr;
            else
                pc  <= pc_next;
                if_id_pc <= pc;
                if_id_instr <= instr_if;
            end if;
        end if;
    end process;

    id_opcode <= if_id_instr(6 downto 0);
    id_rd <= to_integer(unsigned(if_id_instr(11 downto 7)));
    id_funct3 <= if_id_instr(14 downto 12);
    id_rs1 <= to_integer(unsigned(if_id_instr(19 downto 15)));
    id_rs2 <= to_integer(unsigned(if_id_instr(24 downto 20)));
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
    dbg_dmem_memwrite <= dmem_memwrite;
    dbg_dmem_memread <= dmem_memread;
    dbg_dmem_waitrequest <= dmem_waitrequest;
    dbg_reg_file <= reg_file;

    -- --hazard detection
    process(reset, ex_mem_branch_taken, id_rs1, id_rs2, id_ex_rd, id_ex_regwrite,
ex_mem_rd, ex_mem_regwrite, mem_wb_rd, mem_wb_regwrite
)
     begin
         if reset = '1' then
             currently_stalled <= '0';
         elsif  ((id_rs1 = id_ex_rd or
            id_rs2 = id_ex_rd) and id_ex_rd /= 0 and id_ex_regwrite = '1') or
             ((id_rs1 = ex_mem_rd or
             id_rs2 = ex_mem_rd) and ex_mem_rd /= 0 and ex_mem_regwrite = '1') 
          --   ((id_rs1 = mem_wb_rd or
           --  id_rs2 = mem_wb_rd) and mem_wb_rd /= 0 and mem_wb_regwrite = '1')
         then
             currently_stalled <= '1';
         else
             currently_stalled <= '0';
         end if;
     end process;

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
                    if_id_instr(11 downto 8), 32);

            -- U-type
            when "0110111" | "0010111" =>
                id_imm <= if_id_instr(31 downto 12) & x"000";

            -- J-type
            when "1101111" =>
                id_imm <= sign_extend( if_id_instr(31) & if_id_instr(19 downto 12) &
                    if_id_instr(20) &
                    if_id_instr(30 downto 21) , 32);

            when others =>
                id_imm <= (others => '0');
        end case;
    end process;

    -- when the opcode changes, the processor needs to decide what it will do
    process(id_opcode)
    begin
        id_regwrite <= '0';
        id_memread <= '0';
        id_memwrite <= '0';
        id_memtoreg <= '0';
        id_alu_use_imm  <= '0';
        id_branch <= '0';
        id_jump <= '0';

        case id_opcode is
            -- R-type --> Write a result and use two registers
            when "0110011" =>
                id_regwrite <= '1';
                id_alu_use_imm <= '0';

            -- I-type --> writes and uses immediate value
            when "0010011" =>
                id_regwrite <= '1';
                id_alu_use_imm <= '1';

            -- lw --> read memory, write result to register
            when "0000011" =>
                id_regwrite <= '1';
                id_memread <= '1';
                id_memtoreg <= '1';
                id_alu_use_imm <= '1';

            -- store (sw) -- write to memory (not register)
            when "0100011" =>
                id_memwrite <= '1';
                id_regwrite <= '0';
                id_alu_use_imm <= '1';

            -- Branches
            when "1100011" =>
                id_branch <= '1';

            -- jal -- Pc+4
            when "1101111" =>
                id_regwrite <= '1';
                id_jump <= '1';

            -- jalr --> jumps to imm
            when "1100111" =>
                id_regwrite <= '1';
                id_jump <= '1';
                id_alu_use_imm <= '1';

            -- lui --> load imm value in register
            when "0110111" =>
                id_regwrite <= '1';
                --id_alu_use_imm <= '1';

            -- auipc --> rd = Pc+imm
            when "0010111" =>
                id_regwrite <= '1';
                --id_alu_use_imm <= '1';

            when others =>
                null;
        end case;
    end process;

   process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                id_ex_pc          <= (others => '0');
                id_ex_instr       <= (others => '0');
                id_ex_reg1        <= (others => '0');
                id_ex_reg2        <= (others => '0');
                id_ex_imm         <= (others => '0');
                id_ex_rs1         <= 0;
                id_ex_rs2         <= 0;
                id_ex_rd          <= 0;
                id_ex_funct3      <= (others => '0');
                id_ex_funct7      <= (others => '0');
                id_ex_regwrite    <= '0';
                id_ex_memread     <= '0';
                id_ex_memwrite    <= '0';
                id_ex_memtoreg    <= '0';
                id_ex_alu_use_imm <= '0';
                id_ex_branch      <= '0';
                id_ex_jump        <= '0';

            --if a branch is taken we flush the wrong data path
            elsif ex_mem_branch_taken = '1' then
                id_ex_pc          <= (others => '0');
                id_ex_instr       <= x"00000013";
                id_ex_reg1        <= (others => '0');
                id_ex_reg2        <= (others => '0');
                id_ex_imm         <= (others => '0');
                id_ex_rs1         <= 0;
                id_ex_rs2         <= 0;
                id_ex_rd          <= 0;
                id_ex_funct3      <= (others => '0');
                id_ex_funct7      <= (others => '0');
                id_ex_regwrite    <= '0';
                id_ex_memread     <= '0';
                id_ex_memwrite    <= '0';
                id_ex_memtoreg    <= '0';
                id_ex_alu_use_imm <= '0';
                id_ex_branch      <= '0';
                id_ex_jump        <= '0';
	    elsif currently_stalled = '1' then
		-- Freeze IF/ID and then insert bubble between ID/Ex
	        id_ex_instr <= x"00000013";
		id_ex_regwrite    <= '0';
                id_ex_memread     <= '0';
                id_ex_memwrite    <= '0';
                id_ex_memtoreg    <= '0';
                id_ex_branch      <= '0';
                id_ex_jump        <= '0';
                id_ex_rd          <= 0;
            else
                id_ex_pc          <= if_id_pc;
                id_ex_instr       <= if_id_instr;
                id_ex_reg1        <= id_reg1;
                id_ex_reg2        <= id_reg2;
                id_ex_imm         <= id_imm;
                id_ex_rs1         <= id_rs1;
                id_ex_rs2         <= id_rs2;
                id_ex_rd          <= id_rd;
                id_ex_funct3      <= id_funct3;
                id_ex_funct7      <= id_funct7;
                id_ex_regwrite    <= id_regwrite;
                id_ex_memread     <= id_memread;
                id_ex_memwrite    <= id_memwrite;
                id_ex_memtoreg    <= id_memtoreg;
                id_ex_alu_use_imm <= id_alu_use_imm;
                id_ex_branch      <= id_branch;
                id_ex_jump        <= id_jump;
            end if;
        end if;
    end process;


    --choose the ALU input (register or imm)
    ex_alu_in2 <= id_ex_reg2 when id_ex_alu_use_imm = '0' else id_ex_imm;

--Pc = Pc+4 --> for jal and jalr
        ex_link_addr <= std_logic_vector(unsigned(id_ex_pc) + 4);

    --EXE stage
    process(id_ex_reg1, id_ex_reg2, ex_alu_in2, id_ex_instr, id_ex_funct3, id_ex_funct7, id_ex_pc, id_ex_imm)
        variable shift_amount : integer range 0 to 31;
    begin
        ex_alu_result <= (others => '0');
        ex_branch_taken <= '0';
        ex_branch_addr <= (others => '0');
        


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
    			    -- want the lower 32 bits
                            ex_alu_result <= std_logic_vector(resize(signed(id_ex_reg1) * signed(ex_alu_in2), 32));

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
                ex_alu_result <= ex_link_addr; --Pc+4
                ex_branch_addr <= std_logic_vector(unsigned(signed(id_ex_pc)+ signed(id_ex_imm)));
                ex_branch_taken <= '1';

            -- jump and link register
            when "1100111" =>
                --jalr
                ex_alu_result <= ex_link_addr; -- Pc+4
                ex_branch_addr <= std_logic_vector((unsigned(id_ex_reg1) + unsigned(id_ex_imm))and x"FFFFFFFE");
                ex_branch_taken <= '1';

            -- load upper imm
            when "0110111" =>
                --lui
                ex_alu_result <= id_ex_imm;


            -- add uper imm to pc
            when "0010111" =>
                --auipc
                ex_alu_result <= std_logic_vector(unsigned(id_ex_pc)+unsigned(id_ex_imm));

            when others =>
                null;
        end case;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ex_mem_instr        <= (others => '0');
                ex_mem_alu          <= (others => '0');
                ex_mem_reg2         <= (others => '0');
                ex_mem_rd           <= 0;
                ex_mem_funct3       <= (others => '0');
                ex_mem_regwrite     <= '0';
                ex_mem_memread      <= '0';
                ex_mem_memwrite     <= '0';
                ex_mem_memtoreg     <= '0';
                ex_mem_branch_taken <= '0';
                ex_mem_branch_addr  <= (others => '0');
                debug_ex_mem_pc <= (others => '0');
            elsif ex_mem_branch_taken = '1' then
            -- flush wrong-path instruction currently in EX
            ex_mem_instr        <= x"00000013";
            ex_mem_alu          <= (others => '0');
            ex_mem_reg2         <= (others => '0');
            ex_mem_rd           <= 0;
            ex_mem_funct3       <= (others => '0');
            ex_mem_regwrite     <= '0';
            ex_mem_memread      <= '0';
            ex_mem_memwrite     <= '0';
            ex_mem_memtoreg     <= '0';
            ex_mem_branch_taken <= '0';
            ex_mem_branch_addr  <= (others => '0');
            debug_ex_mem_pc     <= (others => '0');
            else
                ex_mem_instr        <= id_ex_instr;
                ex_mem_alu          <= ex_alu_result;
                ex_mem_reg2         <= id_ex_reg2;
                ex_mem_rd           <= id_ex_rd;
                ex_mem_funct3       <= id_ex_funct3;
                ex_mem_regwrite     <= id_ex_regwrite;
                ex_mem_memread      <= id_ex_memread;
                ex_mem_memwrite     <= id_ex_memwrite;
                ex_mem_memtoreg     <= id_ex_memtoreg;
                ex_mem_branch_taken <= ex_branch_taken;
                ex_mem_branch_addr  <= ex_branch_addr;
                debug_ex_mem_pc <= id_ex_pc;
            end if;
        end if;
    end process;

    --MISSING MEMORY STAGE

    process(ex_mem_alu, ex_mem_reg2, ex_mem_memread, ex_mem_memwrite, ex_mem_funct3, dmem_readdata)

    begin
        dmem_address  <= to_integer(unsigned(ex_mem_alu(14 downto 2)));
        dmem_memread  <= ex_mem_memread;
        dmem_memwrite <= ex_mem_memwrite;
        dmem_writedata <= ex_mem_reg2;
        mem_load_data <= (others => '0');

        if ex_mem_memread = '1' and ex_mem_funct3 = "010" then
                --load word
                mem_load_data <= dmem_readdata;
        end if;

    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mem_wb_instr    <= (others => '0');
                mem_wb_alu      <= (others => '0');
                mem_wb_mem      <= (others => '0');
                mem_wb_rd       <= 0;
                mem_wb_regwrite <= '0';
                mem_wb_memtoreg <= '0';
            else
                mem_wb_instr    <= ex_mem_instr;
                mem_wb_alu      <= ex_mem_alu;
                mem_wb_mem      <= mem_load_data;
                mem_wb_rd       <= ex_mem_rd;
                mem_wb_regwrite <= ex_mem_regwrite;
                mem_wb_memtoreg <= ex_mem_memtoreg;
            end if;
        end if;
    end process;

    --writeback process
    wb_data <= mem_wb_mem when mem_wb_memtoreg = '1' else mem_wb_alu;

    process(clk)
    begin
        if rising_edge(clk) then
            if mem_wb_regwrite = '1' and mem_wb_rd /= 0 then --x0 should stay 0
                reg_file(mem_wb_rd) <= wb_data;
            end if;
            reg_file(0) <= (others => '0');
        end if;
    end process;

end architecture;
