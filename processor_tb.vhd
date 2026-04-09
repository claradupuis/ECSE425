library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.types.all;

entity processor_tb is
end processor_tb;

ARCHITECTURE behaviour OF processor_tb IS

    component processor is
        port (
            clk   : in  std_logic;
            reset : in  std_logic
        );
    end component;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    -- Instruction memory --
    signal imem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal imem_readdata    : std_logic_vector(7 downto 0);
    signal imem_address     : integer range 0 to 32767 := 0;
    signal imem_memwrite    : std_logic := '0';
    signal imem_memread     : std_logic := '0';
    signal imem_waitrequest : std_logic;
    -- Data memory --
    signal dmem_writedata   : std_logic_vector(7 downto 0) := (others => '0');
    signal dmem_readdata    : std_logic_vector(7 downto 0);
    signal dmem_address     : integer range 0 to 32767 := 0;
    signal dmem_memwrite    : std_logic := '0';
    signal dmem_memread     : std_logic := '0';
    signal dmem_waitrequest : std_logic;
    -- Register file --
    signal reg_file : reg_array_t;

    signal loading_finished : std_logic := '0';
    signal sim_finished : std_logic := '0';

type char_file_t is file of character;

begin
    dut: entity work.processor
        port map (
            clk   => clk,
            reset => reset,
            -- Instruction Memory -- 
            dbg_imem_writedata => imem_writedata,
            dbg_imem_readdata => imem_readdata,
            dbg_imem_address => imem_address,
            dbg_imem_memwrite => imem_memwrite,
            dbg_imem_memread => imem_memread,
            dbg_imem_waitrequest => imem_waitrequest,
            -- Data memory --
            dbg_dmem_writedata => dmem_writedata,
            dbg_dmem_readdata => dmem_readdata,
            dbg_dmem_address => dmem_address,
            dbg_dmem_memwrite => dmem_memwrite,
            dbg_dmem_memread => dmem_memread,
            dbg_dmem_waitrequest => dmem_waitrequest,
            -- Register file --
            dbg_reg_file =>  reg_file
        );

    -- clock
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for 0.5 ns;
            clk <= '1';
            wait for 0.5 ns;
        end loop;
    end process;

    -- Read program.txt file and put into instruction memory
    -- starting from address 0
    process 
      variable char_buffer : character;
      variable word_buffer : std_logic_vector (31 downto 0);
      variable byte_index : integer range 0 to 3; -- 4 bytes in word
      variable word_address : integer := 0;
      file program : char_file_t open read_mode is "program.txt";
    begin 
      reset <= '1';
      byte_index := 0;
      word_buffer := (others => '0');
      
      while not ENDFILE(program) loop
        read(program, char_buffer); -- read character from file

        -- Convert character into `std_logic_vector` and then insert into the current word
        word_buffer(((byte_index + 1) * 8) - 1 downto byte_index * 8) := std_logic_vector(TO_UNSIGNED(character'pos(char_buffer), 8));

        -- Increment to next byte
        byte_index := byte_index + 1;

        -- Word is complete, write to memory
        if byte_index = 4 then
          imem_memwrite <= '1';
          imem_address <= word_address;
          imem_writedata <= word_buffer;
          wait until rising_edge(clk);

          word_address := word_address + 1;
          byte_index := 0;
          word_buffer := (others => '0');
        end if;
      end loop;

      imem_memwrite <= '0';
      reset <= '0';
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

    -- Writes final contents from memory into "memory.txt"
    process
      variable byte_index : integer range 0 to 3; 
      variable word_address : integer := 0;
      variable line_buffer : line;
      file memory : text open write_mode is "memory.txt";
      variable word_buffer : std_logic_vector (31 downto 0);
    begin
      wait until sim_finished = '1';
      byte_index := 0;
      word_buffer := (others => '0');

      while (word_address < 8192) loop
        dmem_memread <= '1';
        dmem_address <= word_address;
        wait until rising_edge(clk);
        word_buffer := dmem_readdata;

        write(line_buffer, word_buffer);

        writeline(memory, line_buffer);

        word_address := word_address + 1;
      end loop;
      wait;
    end process;

    -- Writes final contents from register file into " w"
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

    -- reset
    reset_process : process
    begin
        reset <= '1';
        wait for 5 ns;
        reset <= '0';
        wait;
    end process;
end;
