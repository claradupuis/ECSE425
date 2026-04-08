library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

ENTITY processor IS
    PORT (
        clk : in std_logic;
        reset : in std_logic
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
    type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
    signal reg_file : reg_array_t := (others => (others => '0')); --sets all to 0 i think

    --pc
    signal pc : integer range 0 to 32767 := 0;

    signal imem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal imem_readdata    : std_logic_vector(7 downto 0);
    signal imem_address     : integer range 0 to 32767 := 0;
    signal imem_memwrite    : std_logic := '0';
    signal imem_memread     : std_logic := '0';
    signal imem_waitrequest : std_logic;

    signal dmem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal dmem_readdata    : std_logic_vector(7 downto 0);
    signal dmem_address     : integer range 0 to 32767 := 0;
    signal dmem_memwrite    : std_logic := '0';
    signal dmem_memread     : std_logic := '0';
    signal dmem_waitrequest : std_logic;

    signal instr_IF : std_logic_vector(31 downto 0);
    signal IF_ID_instr : std_logic_vector(31 downto 0);
    signal IF_ID_pc    : integer range 0 to 32767;
    
    signal ID_EX_instr : std_logic_vector(31 downto 0);
    signal ID_EX_pc    : integer range 0 to 32767;
    
    signal EX_MEM_instr : std_logic_vector(31 downto 0);

    signal MEM_WB_instr : std_logic_vector(31 downto 0);

    signal imem_byte0, imem_byte1, imem_byte2, imem_byte3 : std_logic_vector(7 downto 0);
    signal fetch_counter : integer range 0 to 3 := 0;   

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

--IF logic
    process(clk, reset)
    begin
        if reset = '1' then
            pc       <= 0;
            fetch_counter <= 0;
            reg_file <= (others => (others => '0'));
        elsif rising_edge(clk) then
           
            if (fetch_counter = 0) then
                imem_address <= pc;
                imem_memread <= '1';
                fetch_counter <= 1;

            elsif (fetch_counter = 1) then 
                imem_byte0 <= imem_readdata;
                imem_address <= pc+1;
                fetch_counter <= 2;

            elsif (fetch_counter = 2) then
                imem_byte1<= imem_readdata;
                imem_address <= pc+2;
                fetch_counter <= 3;
            elsif (fetch_counter = 3) then 
                imem_byte2 <= imem_readdata;
                imem_address <= pc+3;
                instr_IF <= imem_byte0 & imem_byte1 & imem_byte2 & imem_readdata;
                pc <= pc+4;
                fetch_counter <= 0;
            end if;

        end if;
    end process;

end architecture;