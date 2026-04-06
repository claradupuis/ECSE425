library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

begin
    dut: entity processor
        port map (
            clk   => clk,
            reset => reset
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

    -- reset
    reset_process : process
    begin
        reset <= '1';
        wait for 5 ns;
        reset <= '0';
        wait;
    end process;
end;