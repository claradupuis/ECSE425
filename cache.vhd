library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity cache is
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
	m_addr : out integer range 0 to 32768-1;
	m_read : out std_logic;
	m_write : out std_logic;
	m_writedata : out std_logic_vector (7 downto 0)
);
end cache;

architecture arch of cache is


	type state_type is (READY, READ_RETURN, MEM_WRITE, MEM_READ, MEM_WRITE_LOOP, MEM_READ_LOOP, WRITE_COMPLETE, WRITE_MEM_READ, WRITE_MEM_READ_LOOP, WRITE_MEM_WRITE, WRITE_MEM_WRITE_LOOP, READ_COMPLETE);
	signal state : state_type;
	signal next_state : state_type;


	CONSTANT LINES : integer := 32;
	CONSTANT WORDS_PER_BLOCK : integer := 4;
	CONSTANT WORD_BITS : integer := 32;
	CONSTANT LINE_BITS : integer := 128;

	CONSTANT INDEX_BITS : integer := 5; --2^5=32
	CONSTANT OFFSET_BITS : integer := 2; --only 2 are used because it is word-aligned
	CONSTANT TAG_BITS : integer := 6; -- 6 = 15-5-4

	--helpful for common lengths
	subtype line_type is std_logic_vector(LINE_BITS-1 downto 0);
	subtype word_type is std_logic_vector(WORD_BITS-1 downto 0);
	subtype tag_type is std_logic_vector(TAG_BITS-1 downto 0);


  --cache storage arrays
	type data_array_type is array (0 to LINES-1) of line_type;
	type tag_array_type is array (0 to LINES-1) of tag_type;

	signal data_array : data_array_type := (others => (others => '0'));
	signal tag_array : tag_array_type := (others => (others => '0'));
	signal valid_bit : std_logic_vector(LINES-1 downto 0) := (others => '0');
	signal dirty_bit : std_logic_vector(LINES-1 downto 0) := (others => '0');

	-- Decoded address fields (using only lower 15 bits)
	signal addr_tag : tag_type;
	signal addr_index : unsigned(INDEX_BITS-1 downto 0);
	signal addr_offset : unsigned(OFFSET_BITS-1 downto 0);
	signal index_i : integer range 0 to LINES-1;

	-- Datapath signals
	signal line_q : line_type;
	signal hit : std_logic; -- 0 or 1
	signal tag_match : std_logic;


	-- Helper Function to extract one 32-bit word from a 128-bit cache line
	function get_word(
		line_in : line_type;
		offset : unsigned(OFFSET_BITS-1 downto 0)
	) return word_type is
		variable start_bit: integer;
		variable stop_bit : integer;
		variable w : word_type;
	begin
		start_bit := to_integer(offset)*WORD_BITS;
		stop_bit := start_bit + WORD_BITS -1;
		w := line_in(stop_bit downto start_bit);

		return w;
	end function;

	--Helper Function to replace one 32-bit word inside a 128-bit cache line
	function set_word(
		line_in : line_type;
		offset : unsigned(OFFSET_BITS-1 downto 0);
		data : word_type
	) return line_type is
		variable start_bit: integer;
		variable stop_bit : integer;
		variable l : line_type := line_in;
	begin
		start_bit := to_integer(offset)*WORD_BITS;
		stop_bit := start_bit + WORD_BITS -1;
		l(stop_bit downto start_bit) := data;

		return l;
	end function;

	function set_byte(
		line_in : line_type;
		offset_word : unsigned(OFFSET_BITS-1 downto 0);
		offset_byte : unsigned(OFFSET_BITS-1 downto 0);
		data : std_logic_vector(7 downto 0)
	) return line_type is
		variable l : line_type := line_in;
		variable start_bit: integer;
		variable stop_bit : integer;
	begin
		start_bit := to_integer(offset_word) * WORD_BITS + to_integer(offset_byte) * 8;
		stop_bit := start_bit + 8 - 1;
		l(stop_bit downto start_bit) := data;
		return l;
	end function;

	variable loop_index_write : integer range 0 to 3 := 0;
	variable loop_index_read : integer range 0 to 3 := 0;

begin


	--split the addresses
	addr_tag <= s_addr(14 downto 9);
	addr_index <= unsigned(s_addr(8 downto 4));
	addr_offset <= unsigned(s_addr(3 downto 2));
	index_i <= to_integer(addr_index);


	--Read cache line and compute Hit
	line_q <= data_array(index_i);
	tag_match <= '1' when tag_array(index_i) = addr_tag else '0';
	hit <= valid_bit(index_i) and tag_match;

	process (clock, reset)
	begin
		if reset = '1' then
			state <= READY;
			--mark lines invalid and clean
			valid_bit <= (others => '0');
			dirty_bit <= (others => '0');
		elsif (clock'event and clock = '1') then
			state <= next_state;
		end if;
	end process;


	--Wite-hit datapath (update the cache storage on Write-Hit)
	process(s_addr,s_read,s_write,s_writedata,m_readdata,m_waitrequest)
		variable new_line : line_type;
	begin
		case state is
			when READY =>
				if (s_read = '1') then
					-- valid && clean/dirty && match
					if (hit = '1') then
						next_state <= READ_RETURN;
					-- invalid/miss
					elsif (hit = '0') then
						-- dirty
						if (dirty_bit(index_i) = '1') then
							next_state <= MEM_WRITE;
						-- clean || invalid (invalid bit cannot be dirty)
						else
							next_state <= MEM_READ;
						end if;
					end if;
					s_waitrequest <= '1';
				elsif s_write = '1' then
					-- valid && match
					if (hit = '1') then
						-- write with dirty bit to 1
						new_line := set_word(data_array(index_i), addr_offset, s_writedata);
						data_array(index_i) <= new_line;
						dirty_bit(index_i) <= '1';
						s_waitrequest <= '0';

						next_state <= WRITE_COMPLETE;

					-- (invalid || miss) && clean
					elsif (dirty_bit(index_i) = '0') then
						-- read into memory then write on top, no need to write back whats there
						next_state <= WRITE_MEM_READ;
						s_waitrequest <= '1';

					-- (invalid || miss) && dirty
					elsif (dirty_bit(index_i) = '1') then
						-- write back what is already there then read in new info
						next_state <= WRITE_MEM_WRITE;
						s_waitrequest <= '1';

					end if;
				else
					s_waitrequest <= '0';
				end if;

			when READ_RETURN =>
				s_waitrequest <= '0';
				s_readdata <= get_word(line_q, addr_offset);
				if (s_read = '0') then
					next_state <= READ_COMPLETE;
				end if;

			when MEM_WRITE =>
				m_addr <= to_integer(unsigned(std_logic_vector(tag_array(index_i)) & std_logic_vector(addr_index) & std_logic_vector(addr_offset) & std_logic_vector(loop_index_write)));
				m_writedata <= get_word(line_q, addr_offset)((loop_index_write * 8) + 7 downto loop_index_write * 8);
				m_write <= '1';
				next_state <= MEM_WRITE_LOOP;

			when MEM_WRITE_LOOP =>
				if (m_waitrequest = '0') then
					m_write <= '0';
					if (loop_index_write = 3) then
						loop_index_write := 0;
						next_state <= MEM_READ;
					else
						loop_index_write := loop_index_write + 1;
						next_state <= MEM_WRITE;
					end if;
				end if;

			when MEM_READ =>
				m_addr <= addr_tag & addr_index & addr_offset & loop_index_read;
				m_read <= '1';
				next_state <= MEM_READ_LOOP;

			when MEM_READ_LOOP =>
				if (m_waitrequest = '0') then
					m_read <= '0';
					new_line := set_byte(data_array(index_i), addr_offset, loop_index_read, m_readdata);
					data_array(index_i) <= new_line;
					dirty_bit(index_i) <= '0';
					if (loop_index_read = 3) then
						loop_index_read := 0;
						next_state <= READ_RETURN;
					else
						loop_index_read := loop_index_read + 1;
						next_state <= MEM_READ;
				end if;

			when WRITE_MEM_WRITE =>
				m_addr <= tag_array(index_i) & addr_index & addr_offset & (loop_index_write / 8;
				m_writedata <= get_word(line_q, addr_offset)(loop_index_write + 7 downto loop_index_write * 8);
				m_write <= '1';
				next_state <= MEM_WRITE_LOOP;

			when WRITE_MEM_WRITE_LOOP =>
				if (m_waitrequest = '0') then
					m_write <= '0';
					if (loop_index_write = 3) then
						loop_index_write := 0;
						next_state <= MEM_READ;
					else
						loop_index_write := loop_index + 8;
						next_state <= MEM_WRITE;
					end if;
				end if;


			when WRITE_MEM_READ =>
				m_addr <= addr_tag & addr_index & addr_offset & (loop_index / 8);
				m_read <= '1';
				next_state <= MEM_READ_LOOP;

			when WRITE_MEM_READ_LOOP =>
				if (m_waitrequest = '0') then
					m_read <= '0';
					new_line := set_byte(data_array(index_i), addr_offset, loop_index_read, m_readdata);
					data_array(index_i) <= new_line;
					dirty_bit(index_i) <= '0';
					if (loop_index_read = 3) then
						loop_index_read := 0;

						new_line := set_word(data_array(index_i), addr_offset, s_writedata);
						data_array(index_i) <= new_line;
						dirty_bit(index_i) <= '1';
						s_waitrequest <= '0';

						next_state <= WRITE_COMPLETE;
					else
						next_state <= WRITE_MEM_READ;
				end if;

			when WRITE_COMPLETE =>
				next_state <= READY
		end if;
	end if;
end process;


end arch;
