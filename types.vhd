library ieee;
use ieee.std_logic_1164.all;
package types is
    type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
end package types;
