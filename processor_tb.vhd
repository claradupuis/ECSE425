library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.types.all;

entity processor_tb is
end processor_tb;

ARCHITECTURE behaviour OF processor_tb IS

    component processor is
        port (
            clk              : in  std_logic;
            reset            : in  std_logic;
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
            dbg_reg_file         : out reg_array_t;
            ld_imem_addr         : in  integer range 0 to 8191;
            ld_imem_data         : in  std_logic_vector(31 downto 0);
            ld_imem_write        : in  std_logic
        );
    end component;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    -- Instruction memory --
    signal imem_writedata   : std_logic_vector(31 downto 0) := (others => '0');
    signal imem_readdata    : std_logic_vector(31 downto 0);
    signal imem_address     : integer range 0 to 32767 := 0;
    signal imem_memwrite    : std_logic := '0';
    signal imem_memread     : std_logic := '0';
    signal imem_waitrequest : std_logic;
    -- Data memory --
    signal dmem_writedata   : std_logic_vector(31 downto 0) := (others => '0');
    signal dmem_readdata    : std_logic_vector(31 downto 0);
    signal dmem_address     : integer range 0 to 32767 := 0;
    signal dmem_memwrite    : std_logic := '0';
    signal dmem_memread     : std_logic := '0';
    signal dmem_waitrequest : std_logic;
    -- Register file --
    signal reg_file : reg_array_t;

    -- Instruction memory loader signals
    signal ld_imem_addr  : integer range 0 to 8191 := 0;
    signal ld_imem_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal ld_imem_write : std_logic := '0';

    signal loading_finished : std_logic := '0';
    signal sim_finished : std_logic := '0';

begin
    dut: entity work.processor
        port map (
            clk   => clk,
            reset => reset,
            -- Instruction Memory (debug observe only) --
            dbg_imem_writedata   => imem_writedata,
            dbg_imem_readdata    => imem_readdata,
            dbg_imem_address     => imem_address,
            dbg_imem_memwrite    => imem_memwrite,
            dbg_imem_memread     => imem_memread,
            dbg_imem_waitrequest => imem_waitrequest,
            -- Data memory (debug observe only) --
            dbg_dmem_writedata   => dmem_writedata,
            dbg_dmem_readdata    => dmem_readdata,
            dbg_dmem_address     => dmem_address,
            dbg_dmem_memwrite    => dmem_memwrite,
            dbg_dmem_memread     => dmem_memread,
            dbg_dmem_waitrequest => dmem_waitrequest,
            -- Register file --
            dbg_reg_file         => reg_file,
            -- Instruction memory loader --
            ld_imem_addr         => ld_imem_addr,
            ld_imem_data         => ld_imem_data,
            ld_imem_write        => ld_imem_write
        );

    -- clock
    clk_process : process
    begin
        while sim_finished = '0' loop
            clk <= '0';
            wait for 0.5 ns;
            clk <= '1';
            wait for 0.5 ns;
        end loop;
        wait;
    end process;

    -- Read program.txt (one 32-bit binary string per line) into instruction memory.
    -- reset is held high during loading so the pipeline stays flushed.
    process
      file program      : text open read_mode is "program.txt";
      variable line_buf : line;
      variable instr    : std_logic_vector(31 downto 0);
      variable word_address : integer := 0;
    begin
      reset         <= '1';
      ld_imem_write <= '0';

      while not ENDFILE(program) loop
        readline(program, line_buf);
        if line_buf'length > 0 then
          read(line_buf, instr);
          
          ld_imem_addr  <= word_address;
          ld_imem_data  <= instr;
		ld_imem_write <= '1';

          wait until rising_edge(clk);
	  wait until rising_edge(clk);
	  ld_imem_write <= '0';
	  wait until rising_edge(clk);
	
          word_address  := word_address + 1;
        end if;
      end loop;

      ld_imem_write    <= '0';
      reset            <= '0';
      loading_finished <= '1';
      wait;
    end process;

    -- Run the processor for 10000 cc
    process
      variable cc : integer := 0;
    begin
      wait until loading_finished = '1';

      while cc < 10000 loop
        wait until rising_edge(clk);
        cc := cc + 1;
      end loop;

      sim_finished <= '1';
      wait;
    end process;

    -- NOTE: data memory dump is handled by testbench.tcl which can access
    -- sim:/processor_tb/dut/data_mem/ram_block directly after run -all

    -- Writes final contents from register file into text file
    process 
      file registers : text open write_mode is "register_file.txt";
      variable line_buf : line;
    begin
      wait until sim_finished = '1';
      
      for i in reg_file'range loop
        write(line_buf, reg_file(i));
        writeline(registers, line_buf);
      end loop;
    end process;

end;
