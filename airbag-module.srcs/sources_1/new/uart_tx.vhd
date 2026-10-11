-- UART transmitter, 8N1, LSB first. 100 MHz / 115200 = 868 clocks per bit.
library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
  generic (CLKS_PER_BIT : positive := 868);
  port (
    clk, rst : in  std_logic;
    start    : in  std_logic;                     -- 1-cycle pulse (ignored if busy)
    data     : in  std_logic_vector(7 downto 0);
    busy     : out std_logic;
    tx       : out std_logic := '1'
  );
end entity;

architecture rtl of uart_tx is
  signal busy_i  : std_logic := '0';
  signal shreg   : std_logic_vector(9 downto 0) := (others => '1');
  signal clk_cnt : integer range 0 to CLKS_PER_BIT-1 := 0;
  signal bit_cnt : integer range 0 to 9 := 0;
begin
  busy <= busy_i;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        busy_i <= '0'; tx <= '1'; clk_cnt <= 0; bit_cnt <= 0;
      elsif busy_i = '0' then
        tx <= '1';
        if start = '1' then
          shreg   <= '1' & data & '0';   -- stop, data(7..0), start
          tx      <= '0';                -- start bit
          busy_i  <= '1';
          clk_cnt <= 0;
          bit_cnt <= 0;
        end if;
      else
        if clk_cnt = CLKS_PER_BIT-1 then
          clk_cnt <= 0;
          if bit_cnt = 9 then
            busy_i <= '0';
            tx     <= '1';
          else
            bit_cnt <= bit_cnt + 1;
            tx      <= shreg(bit_cnt + 1);
          end if;
        else
          clk_cnt <= clk_cnt + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;