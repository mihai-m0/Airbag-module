--Spi Communciation protocol
--Cpol=0 , Cpha=0
library ieee;
use ieee.std_logic_1164.all;

entity spi_master is
  generic (HALF_PERIOD : positive := 50);
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;                      -- single-cycle pulse
    tx_data : in  std_logic_vector(7 downto 0);
    rx_data : out std_logic_vector(7 downto 0);   -- valid when done = '1'
    done    : out std_logic;                      -- single-cycle pulse
    sclk    : out std_logic;
    mosi    : out std_logic;
    miso    : in  std_logic
  );
end entity;

architecture rtl of spi_master is
  type state_type is (IDLE, XFER);
  signal state    : state_type := IDLE;
  signal clk_cnt  : integer range 0 to HALF_PERIOD-1 := 0;
  signal bit_cnt  : integer range 0 to 7 := 0;
  signal tx_shift : std_logic_vector(7 downto 0):= x"00";
  signal rx_shift : std_logic_vector(7 downto 0):= x"00";
  signal sclk_i   : std_logic := '0'; --our own clock which is the main clock,divided so it reches 1Hz
  signal miso_s1, miso_s2 : std_logic := '0';
begin
  sclk <= sclk_i;

  process(clk)
  begin
    if rising_edge(clk) then
      miso_s1 <= miso;          -- 2-flop synchronizer for the async input
      miso_s2 <= miso_s1;       -- used 2 signals to handle metastability
      done    <= '0';

      if rst = '1' then
        state <= IDLE; sclk_i <= '0'; mosi <= '0';
        clk_cnt <= 0; bit_cnt <= 0;
      else
        case state is
          when IDLE =>
            sclk_i <= '0';
            if start = '1' then
              tx_shift <= tx_data;
              mosi     <= tx_data(7);     -- first bit ready before first rising edge
              clk_cnt  <= 0;
              bit_cnt  <= 0;
              state    <= XFER;
            end if;

          when XFER =>
            if clk_cnt = HALF_PERIOD-1 then
              clk_cnt <= 0;
              if sclk_i = '0' then        --on the rising edge we sample miso
                sclk_i   <= '1';
                rx_shift <= rx_shift(6 downto 0) & miso_s2;
              else                        --on the falling edge we shift
                sclk_i <= '0';
                if bit_cnt = 7 then
                  state   <= IDLE;
                  done    <= '1';
                  rx_data <= rx_shift;
                else
                  bit_cnt  <= bit_cnt + 1;
                  mosi     <= tx_shift(6);
                  tx_shift <= tx_shift(6 downto 0) & '0';
                end if;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;