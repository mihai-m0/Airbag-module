-- On each sample_valid, sends a 7-byte frame:  AA  XH XL  YH YL  ZH ZL
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sample_streamer is
  port (
    clk, rst     : in  std_logic;
    sample_valid : in  std_logic;
    acc_x, acc_y, acc_z : in signed(15 downto 0);
    tx_busy      : in  std_logic;
    tx_start     : out std_logic;
    tx_data      : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of sample_streamer is
  type state_t is (S_IDLE, S_PULSE, S_GAP, S_WAIT);
  type buf_t is array (0 to 6) of std_logic_vector(7 downto 0);
  signal state : state_t := S_IDLE;
  signal buf   : buf_t := (others => (others => '0'));
  signal idx   : integer range 0 to 6 := 0;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      tx_start <= '0';
      if rst = '1' then
        state <= S_IDLE; idx <= 0;
      else
        case state is
          when S_IDLE =>
            if sample_valid = '1' then
              buf(0) <= x"AA";
              buf(1) <= std_logic_vector(acc_x(15 downto 8));
              buf(2) <= std_logic_vector(acc_x(7 downto 0));
              buf(3) <= std_logic_vector(acc_y(15 downto 8));
              buf(4) <= std_logic_vector(acc_y(7 downto 0));
              buf(5) <= std_logic_vector(acc_z(15 downto 8));
              buf(6) <= std_logic_vector(acc_z(7 downto 0));
              idx    <= 0;
              state  <= S_PULSE;
            end if;

          when S_PULSE =>
            if tx_busy = '0' then
              tx_data  <= buf(idx);
              tx_start <= '1';
              state    <= S_GAP;
            end if;

          when S_GAP =>                  -- give the UART one cycle to raise busy
            state <= S_WAIT;

          when S_WAIT =>
            if tx_busy = '0' then
              if idx = 6 then
                state <= S_IDLE;
              else
                idx   <= idx + 1;
                state <= S_PULSE;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;