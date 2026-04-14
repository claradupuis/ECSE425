library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cache is
generic (
    ram_size : integer := 32768
);

port(
    clock : in std_logic;
    reset : in std_logic;

    -- Avalon interface --
    s_addr : in std_logic_vector (31 downto 0);
    s_read : in std_logic;
    s_write : in std_logic;
    s_writedata : in std_logic_vector (31 downto 0);
    m_readdata : in std_logic_vector (7 downto 0);
    m_waitrequest : in std_logic;

    s_waitrequest : out std_logic;
    s_readdata : out std_logic_vector (31 downto 0);
    m_addr : out integer range 0 to ram_size-1;
    m_read : out std_logic;
    m_write : out std_logic;
    m_writedata : out std_logic_vector (7 downto 0)
);
end cache;

architecture arch of cache is

    constant LINES           : integer := 32;
    constant WORD_BITS       : integer := 32;
    constant LINE_BITS       : integer := 128;
    constant BYTES_PER_BLOCK : integer := 16;
    constant INDEX_BITS      : integer := 5;
    constant OFFSET_BITS     : integer := 2;
    constant TAG_BITS        : integer := 6;

    subtype line_type is std_logic_vector(LINE_BITS-1 downto 0);
    subtype word_type is std_logic_vector(WORD_BITS-1 downto 0);
    subtype tag_type  is std_logic_vector(TAG_BITS-1 downto 0);

    type data_array_type is array (0 to LINES-1) of line_type;
    type tag_array_type  is array (0 to LINES-1) of tag_type;

    signal data_array : data_array_type := (others => (others => '0'));
    signal tag_array  : tag_array_type  := (others => (others => '0'));
    signal valid_bit  : std_logic_vector(LINES-1 downto 0) := (others => '0');
    signal dirty_bit  : std_logic_vector(LINES-1 downto 0) := (others => '0');

    signal req_addr      : std_logic_vector(31 downto 0) := (others => '0');
    signal req_writedata : word_type := (others => '0');
    signal req_read      : std_logic := '0';
    signal req_write     : std_logic := '0';

    signal req_tag       : tag_type := (others => '0');
    signal req_index     : unsigned(INDEX_BITS-1 downto 0) := (others => '0');
    signal req_offset    : unsigned(OFFSET_BITS-1 downto 0) := (others => '0');
    signal req_index_int   : integer range 0 to LINES-1 := 0;

    signal byte_count    : integer range 0 to BYTES_PER_BLOCK-1 := 0;

    type state_type is (
        READY,
        DECISION,
        WRITEBACK,
        WAIT_WRITEBACK,
        FILL_LINE,
        WAIT_FILL,
        READ_COMPLETE,
        WRITE_COMPLETE
    );
    signal state : state_type := READY;

    function get_word(
        line_in : line_type;
        offset  : unsigned(OFFSET_BITS-1 downto 0)
    ) return word_type is
        variable start_bit : integer;
        variable stop_bit  : integer;
    begin
        start_bit := to_integer(offset) * WORD_BITS;
        stop_bit  := start_bit + WORD_BITS - 1;
        return line_in(stop_bit downto start_bit);
    end function;

    function set_word(
        line_in : line_type;
        offset  : unsigned(OFFSET_BITS-1 downto 0);
        data    : word_type
    ) return line_type is
        variable l : line_type := line_in;
        variable start_bit : integer;
        variable stop_bit  : integer;
    begin
        start_bit := to_integer(offset) * WORD_BITS;
        stop_bit  := start_bit + WORD_BITS - 1;
        l(stop_bit downto start_bit) := data;
        return l;
    end function;

    function set_byte(
        line_in    : line_type;
        byte_index : integer range 0 to BYTES_PER_BLOCK-1;
        data       : std_logic_vector(7 downto 0)
    ) return line_type is
        variable l : line_type := line_in;
        variable start_bit : integer;
        variable stop_bit  : integer;
    begin
        start_bit := byte_index * 8;
        stop_bit  := start_bit + 7;
        l(stop_bit downto start_bit) := data;
        return l;
    end function;

	--computes base address of requested block
    function req_base_addr(a : std_logic_vector(31 downto 0)) return integer is
    begin
        return to_integer(unsigned(a(14 downto 4))) * 16;
    end function;

	--when dirty line is evicted need to know where in main memory the block belongs
    function current_base_addr(
        t   : tag_type;
        idx : unsigned(INDEX_BITS-1 downto 0)
    ) return integer is
    begin
        return (to_integer(unsigned(t)) * LINES + to_integer(idx)) * 16;
    end function;

begin

    req_tag     <= req_addr(14 downto 9);
    req_index   <= unsigned(req_addr(8 downto 4));
    req_offset  <= unsigned(req_addr(3 downto 2));
    req_index_int <= to_integer(unsigned(req_addr(8 downto 4)));

    process(clock, reset)
        variable tmp_line : line_type;
    begin
        if reset = '1' then
            state         <= READY;
            data_array    <= (others => (others => '0'));
            tag_array     <= (others => (others => '0'));
            valid_bit     <= (others => '0');
            dirty_bit     <= (others => '0');
            req_addr      <= (others => '0');
            req_writedata <= (others => '0');
            req_read      <= '0';
            req_write     <= '0';
            byte_count    <= 0;

        elsif rising_edge(clock) then
            
			if state = READY then 
				if s_read = '1' or s_write = '1' then
                    req_addr      <= s_addr;
                    req_writedata <= s_writedata;
                    req_read      <= s_read;
                    req_write     <= s_write;
                    state         <= DECISION;
                end if;
			
			elsif state = DECISION then 
				if req_read = '1' then
                     if valid_bit(req_index_int) = '1' and tag_array(req_index_int) = req_tag then
                        state <= READ_COMPLETE;
                    elsif valid_bit(req_index_int) = '1' and dirty_bit(req_index_int) = '1' then
                        byte_count <= 0;
                        state <= WRITEBACK;
                    else
                        byte_count <= 0;
                        state <= FILL_LINE;
                    end if;

                elsif req_write = '1' then
                    if valid_bit(req_index_int) = '1' and tag_array(req_index_int) = req_tag then
                        data_array(req_index_int) <= set_word(data_array(req_index_int), req_offset, req_writedata);
                        valid_bit(req_index_int)  <= '1';
                        dirty_bit(req_index_int)  <= '1';
                        state <= WRITE_COMPLETE;
                    elsif valid_bit(req_index_int) = '1' and dirty_bit(req_index_int) = '1' then
                        byte_count <= 0;
                        state <= WRITEBACK;
                    else
                        byte_count <= 0;
                        state <= FILL_LINE;
                    end if;
                else
                    state <= READY;
                end if;
			
			elsif state = WRITEBACK then 
				state <= WAIT_WRITEBACK;
			
			elsif state = WAIT_WRITEBACK then 
				if m_waitrequest = '0' then
                    if byte_count = BYTES_PER_BLOCK-1 then
                        dirty_bit(req_index_int) <= '0';
                        byte_count <= 0;
                        state <= FILL_LINE;
                    else
                        byte_count <= byte_count + 1;
                        state <= WRITEBACK;
                    end if;
                end if;			

			elsif state = FILL_LINE then 
				state <= WAIT_FILL;
			
			elsif state = WAIT_FILL then 
				if m_waitrequest = '0' then
                    tmp_line := set_byte(data_array(req_index_int), byte_count, m_readdata);

                    if byte_count = BYTES_PER_BLOCK-1 then
                        if req_write = '1' then
                            tmp_line := set_word(tmp_line, req_offset, req_writedata);
                            dirty_bit(req_index_int) <= '1';
                            state <= WRITE_COMPLETE;
                        else
                            dirty_bit(req_index_int) <= '0';
                            state <= READ_COMPLETE;
                        end if;

                        data_array(req_index_int) <= tmp_line;
                        tag_array(req_index_int)  <= req_tag;
                        valid_bit(req_index_int)  <= '1';
                        byte_count <= 0;
                    else
                        data_array(req_index_int) <= tmp_line;
                        byte_count <= byte_count + 1;
                        state <= FILL_LINE;
                    end if;
                end if;

			elsif state = READ_COMPLETE then 
				req_read  <= '0';
                req_write <= '0';
                state <= READY;
				
			elsif state = WRITE_COMPLETE then 
				req_read  <= '0';
                req_write <= '0';
            	state <= READY;
				
			end if;

	
        end if;
    end process;

    process(state, reset, req_addr, req_offset, req_index, req_index_int, byte_count,
            data_array, tag_array)
    begin
        s_waitrequest <= '1';
        s_readdata    <= (others => '0');
        m_addr        <= 0;
        m_read        <= '0';
        m_write       <= '0';
        m_writedata   <= (others => '0');

        if reset = '1' then
            s_waitrequest <= '1';
        else
            if state = READY then
                null;

        	elsif state = DECISION then
                null;

            elsif state =  WRITEBACK then
                m_addr      <= current_base_addr(tag_array(req_index_int), req_index) + byte_count;
                m_writedata <= data_array(req_index_int)(byte_count*8 + 7 downto byte_count*8);
                m_write     <= '1';

            elsif state = WAIT_WRITEBACK then
                null;

            elsif state = FILL_LINE then
                m_addr <= req_base_addr(req_addr) + byte_count;
                m_read <= '1';

        	elsif state = WAIT_FILL then
                null;

            elsif state = READ_COMPLETE then
                s_waitrequest <= '0';
                s_readdata    <= get_word(data_array(req_index_int), req_offset);

            elsif state = WRITE_COMPLETE then
                s_waitrequest <= '0';
            end if;
        end if;
    end process;

end arch;