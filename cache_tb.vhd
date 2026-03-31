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

        constant A0  : integer := 16#000#;
        constant A1  : integer := 16#200#;

        constant B0  : integer := 16#020#;
        constant B1  : integer := 16#220#;

        constant C0  : integer := 16#040#;
        constant C1  : integer := 16#240#;

        constant WD1 : std_logic_vector(31 downto 0) := x"DEADBEEF";
        constant WD2 : std_logic_vector(31 downto 0) := x"CAFEBABE";
        constant WD3 : std_logic_vector(31 downto 0) := x"AAAAAAAA";
        constant WD4 : std_logic_vector(31 downto 0) := x"12345678";
        constant WD5 : std_logic_vector(31 downto 0) := x"EEEEEEEE";

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
        -- Cache fetches from memory 
        do_read(A0, mem_word(A0), "TC1: invalid line, read miss");
        
         -- TEST CASE 2:
        -- line is not valid. A0 is not dirty so no writeback
        -- Cache fetches from memory 
        do_write(B0, mem_word(B0), "TC2: invalid line, write miss");
        
        -- TEST CASE 3: 
        -- A0 is now in cache --> hit 
        -- no memory access
        do_read(A0, mem_word(A0), "TC:3 clean line, read hit");

         -- TEST CASE 4: 
        -- A0 is in cache and clean --> no writeback
        -- valid but tag not equal
        do_write(A1, WD1, "TC4: clean line, write hit");

 
        -- TEST CASE 5: 
        -- A1 maps to same index. Tag equal. dirty 
        do_read(A1, WD1, "TC5: clean victim, read miss");

       
        -- TEST CASE 6: 
        -- A1 is in cache and clean --> hit. No memory access
        -- cache updates word and sets dirty bit.
        do_write(A1, WD1, "TC6: clean line, write hit");

    
        -- TEST CASE 7:
        -- A1 is in cache (and is dirty) -> hit
        -- data returned from cache
        do_read(A1, WD1, "TC7: dirty line, read hit");

        
        -- TEST CASE 8:
        -- Writing to A1 --> hit 
        -- cache updates word and A1 remains dirty
        do_write(A1, WD3, "TC8: dirty line, write hit");
        --verify updated value
        do_read(A1, WD3, "TC8 verify: dirty hit stores newest data");


        -- TEST CASE 9: 
        -- A1 is in cache and dirty 
        -- Access A0 --> miss
        -- cache needs to writeback A1 to memory and load A0
        do_read(A0, mem_word(A0), "TC9: dirty victim, read miss (writeback)");
        --verify that writeback worked
        do_read(A1, WD3, "TC9 verify: writeback preserved old dirty data");

       
        -- TEST CASE 10: 
        -- B0 not in cache --> miss 
        -- write-allocate (Load B0 from memory, update word, mark line dirty)
        do_write(B0, WD2, "TC10: invalid line, write miss (write-allocate)");

        
        -- TEST CASE 11: 
        -- Acces B1 --> miss
        -- B0 is dirty so need to writeback B0, load B1
        -- write performed on B1 and mark as dirty
        do_write(B1, WD4, "TC11: dirty victim, write miss (writeback + allocate)");
        do_read(B1, WD4, "TC11 verify: new dirty line stores written data");
        do_read(B0, WD2, "TC11 verify: evicted dirty line written back");

        
        -- TEST CASE 12: valid clean + write + miss
        -- load C0. in cache 
        do_read(C0, mem_word(C0), "TC12 setup: load clean line");
        -- C1 not in cache. Don't need writeback. replace block and perform write
        do_write(C1, WD5, "TC12: clean victim, write miss (allocate only)");
        --verify that data is correctly stored
        do_read(C1, WD5, "TC12 verify: clean-victim miss stores written data");
        --verify no corruption 
        do_read(C0, mem_word(C0), "TC12 verify: clean eviction caused no corruption");

        report "All relevant cache access cases completed." severity note;
        report  "ALL TESTS PASSED" severity note;

        wait;
    end process;

end tb;