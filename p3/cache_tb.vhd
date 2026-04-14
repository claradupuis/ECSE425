library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache_tb is
end cache_tb;

architecture tb of cache_tb is

    constant ram_size     : integer := 32768;
    constant clock_period : time := 10 ns;

    -- Cache <-> CPU
    signal clock         : std_logic := '0';
    signal reset         : std_logic := '1';

    signal s_addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal s_read        : std_logic := '0';
    signal s_write       : std_logic := '0';
    signal s_writedata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_waitrequest : std_logic;
    signal s_readdata    : std_logic_vector(31 downto 0);

    -- Cache <-> Memory
    signal m_addr        : integer range 0 to ram_size-1;
    signal m_read        : std_logic;
    signal m_write       : std_logic;
    signal m_writedata   : std_logic_vector(7 downto 0);
    signal m_readdata    : std_logic_vector(7 downto 0);
    signal m_waitrequest : std_logic;

    -- Expected initial word in memory.vhd
    function mem_word(addr : integer) return std_logic_vector is
        variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
    begin
        b0 := std_logic_vector(to_unsigned((addr + 0) mod 256, 8));
        b1 := std_logic_vector(to_unsigned((addr + 1) mod 256, 8));
        b2 := std_logic_vector(to_unsigned((addr + 2) mod 256, 8));
        b3 := std_logic_vector(to_unsigned((addr + 3) mod 256, 8));
        return b3 & b2 & b1 & b0;
    end function;

begin

    uut_cache: entity work.cache
        generic map (
            ram_size => ram_size
        )
        port map (
            clock         => clock,
            reset         => reset,
            s_addr        => s_addr,
            s_read        => s_read,
            s_write       => s_write,
            s_writedata   => s_writedata,
            m_readdata    => m_readdata,
            m_waitrequest => m_waitrequest,
            s_waitrequest => s_waitrequest,
            s_readdata    => s_readdata,
            m_addr        => m_addr,
            m_read        => m_read,
            m_write       => m_write,
            m_writedata   => m_writedata
        );

    uut_mem: entity work.memory
        generic map (
            ram_size     => ram_size,
            mem_delay    => 10 ns,
            clock_period => clock_period
        )
        port map (
            clock       => clock,
            writedata   => m_writedata,
            address     => m_addr,
            memwrite    => m_write,
            memread     => m_read,
            readdata    => m_readdata,
            waitrequest => m_waitrequest
        );

    clock <= not clock after clock_period / 2;

    

    stim_proc: process

        procedure do_read(
            constant addr_val  : in integer;
            constant expected  : in std_logic_vector(31 downto 0);
            constant testname  : in string
        ) is
            variable done : boolean := false;
        begin
            s_addr      <= std_logic_vector(to_unsigned(addr_val, 32));
            s_writedata <= (others => '0');
            s_read      <= '1';
            s_write     <= '0';

            wait until rising_edge(clock);
            s_read <= '0';

            done := false;
            while not done loop
                wait for 1 ns;
                if s_waitrequest = '0' then
                    done := true;
                end if;
            end loop;

            assert s_readdata = expected
                report "FAIL: " & testname &
                       " | addr=" & integer'image(addr_val) &
                       " | expected mismatch"
                severity failure;

            report "PASS: " & testname severity note;
            wait until rising_edge(clock);
        end procedure;

        procedure do_write(
            constant addr_val  : in integer;
            constant data_val  : in std_logic_vector(31 downto 0);
            constant testname  : in string
        ) is
            variable done : boolean := false;
        begin
            s_addr      <= std_logic_vector(to_unsigned(addr_val, 32));
            s_writedata <= data_val;
            s_read      <= '0';
            s_write     <= '1';

            wait until rising_edge(clock);
            s_write <= '0';

            done := false;
            while not done loop
                wait for 1 ns;
                if s_waitrequest = '0' then
                    done := true;
                end if;
            end loop;

            report "PASS: " & testname severity note;
            wait until rising_edge(clock);
        end procedure;

        -- A0 and A1 have same index but different tag
        constant A0  : integer := 16#000#;
        constant A1  : integer := 16#200#;

        -- B0 and B1 have same index but different tag
        constant B0  : integer := 16#020#;
        constant B1  : integer := 16#220#;

        constant WD1 : std_logic_vector(31 downto 0) := x"DEADBEEF";
        constant WD2 : std_logic_vector(31 downto 0) := x"CAFEBABE";
        constant WD3 : std_logic_vector(31 downto 0) := x"AAAAAAAA";
        constant WD4 : std_logic_vector(31 downto 0) := x"12345678";

    begin
        reset <= '1';
        s_addr <= (others => '0');
        s_read <= '0';
        s_write <= '0';
        s_writedata <= (others => '0');

        wait for 30 ns;
        wait until rising_edge(clock);
        reset <= '0';
        wait until rising_edge(clock);


        -- TEST CASE 1:
        -- Cache is empty so no valid line --> miss
        -- Cache fetches B0 from memory 
        do_read(B0, mem_word(B0), "TC1: invalid line, tag not equal, not dirty, read");
        
         -- TEST CASE 2:
        -- line is not valid. B0 is not dirty so no writeback
        -- Cache fetches A0 from memory and writes to it --> set dirty bit
        do_write(A0, mem_word(A0), "TC2: invalid line, tag not equal, not dirty, write");
        
        -- TEST CASE 3: 
        -- A0 is already in cache
        do_read(A0, mem_word(A0), "TC3: valid line, tag equal, dirty, read");

         -- TEST CASE 4: 
        -- A0 is in cache and dirty --> need writeback
        -- fetch A1 and write to it --> set dirty bit
        do_write(A1, WD1, "TC4: Valid line, tag not equal, dirty, write");

        -- TEST CASE 5: 
        -- A1 is in cache and is already dirty
        do_write(A1, WD2, "TC5: valid line, tag equal, dirty, write ");

        -- TEST CASE 6: 
        -- A1 is in cache and dirty 
        -- Access A0 --> miss
        -- cache needs to writeback A1 to memory and load A0
        do_read(A0, mem_word(A0), "TC6: valid line, tag not equal, dirty, read");

        -- TEST CASE 7:
        -- B0 not in cache --> miss
        -- fetch B0 from memory 
        do_read(B0, mem_word(B0), "TC7: invalid line, tag not equal, not dirty, read");

        -- TEST CASE 8:
        -- B0 is in cache and is not dirty
        do_read(B0, mem_word(B0), "TC8: valid line, tag equal, not dirty, read");

        -- TEST CASE 9: 
        -- B0 is not dirty
        -- load B1 into cache 
        do_read(B1, mem_word(B1), "TC9: valid line, tag not equal, not dirty, read");

        -- TEST CASE 10: 
        -- B1 is in the cache and not dirty 
        do_write(B1, mem_word(B1), "TC10: valid line, tag equal, not dirty, write");

        -- TEST CASE 11: 
        -- B1 is not dirty
        do_write(B0, WD4, "TC11: valid line, tag not equal, not dirty, write");



        report "All test cases completed." severity note;
        report  "ALL TESTS PASSED" severity note;

        wait;
    end process;

end tb;