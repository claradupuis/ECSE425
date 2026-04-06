library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

ENTITY processor IS
    PORT (
        clk : in std_logic;
        reset : in std_logic;
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
    signal reg_file : reg_array_t := (others => (others => '0')) --sets all to 0 i think

    --pc
    signal pc : integer range 0 to 32767 := 0;

begin
    instruction_mem : entity memory
        generic map (
            ram_size     => 32768,
            mem_delay    => 10 ns,
            clock_period => 1 ns
        )
        port map (
            clock       => clk,
            writedata   => instr_writedata,
            address     => instr_address,
            memwrite    => instr_memwrite,
            memread     => instr_memread,
            readdata    => instr_readdata,
            waitrequest => instr_waitrequest
        );

    data_mem : entity work.memory
        generic map (
            ram_size     => 32768,
            mem_delay    => 10 ns,
            clock_period => 1 ns
        )
        port map (
            clock       => clk,
            writedata   => data_writedata,
            address     => data_address,
            memwrite    => data_memwrite,
            memread     => data_memread,
            readdata    => data_readdata,
            waitrequest => data_waitrequest
        );