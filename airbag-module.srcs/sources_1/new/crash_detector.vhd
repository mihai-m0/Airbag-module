-- For X and Y separately it adds up the last WINDOW calibrated samples. That sum is proportional
-- to the change of speed over the window (acceleration added up over time).The metric is
--        |sum of X| + |sum of Y|
-- and the detector deploys when the metric is above THRESHOLD, in any horizontal direction.
-- Slow events (the gentle push when a slide starts, tilting) add up to little within a short period
-- a sharp stop adds up to a lot.
--
--   ST_WAIT_CAL : wait until the calibrator knows the resting baseline
--   ST_ARMED    : on every new sample, update the two sums and compare
--   ST_DEPLOYED : latched; only a reset gets out
--
-- Units: 1 LSB = 4 mg at +/-8 g, so THRESHOLD = 1500 means |sum X| + |sum Y| above 6 g
-- when 4 samples are added (0.015 g*s at 400 Hz).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crash_detector is
  generic (
    WINDOW    : integer := 4;       -- samples added up (4 samples = 10 ms at 400 Hz), must be >= 1
    THRESHOLD : integer := 1500     -- in LSB; chosen from recordings
  );
  port (
    clk, rst     : in  std_logic;
    calibrated   : in  std_logic;
    rel_valid    : in  std_logic;                --1-cycle pulse: rel_x/rel_y hold a new sample
    rel_x, rel_y : in  signed(15 downto 0);      --the calibrated readings
    armed        : out std_logic;
    deployed     : out std_logic
  );
end entity;

architecture rtl of crash_detector is
  constant SUM_W : integer := 24;                -- room for the sum of up to 256 16-bit values
  type state_t is (ST_WAIT_CAL, ST_ARMED, ST_DEPLOYED);
  type buf_t   is array (0 to WINDOW-1) of signed(15 downto 0);
  signal state : state_t := ST_WAIT_CAL;
  signal buf_x, buf_y : buf_t := (others => (others => '0'));   -- the last WINDOW samples
  signal sum_x, sum_y : signed(SUM_W-1 downto 0) := (others => '0');
begin
  armed    <= '1' when state = ST_ARMED    else '0';
  deployed <= '1' when state = ST_DEPLOYED else '0';

  process(clk)
    variable nx, ny : signed(SUM_W-1 downto 0);  -- the new sums, available immediately
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= ST_WAIT_CAL;
        buf_x <= (others => (others => '0'));
        buf_y <= (others => (others => '0'));
        sum_x <= (others => '0');
        sum_y <= (others => '0');
      else
        case state is
          when ST_WAIT_CAL =>
            if calibrated = '1' then
              state <= ST_ARMED;
            end if;

          when ST_ARMED =>
            if rel_valid = '1' then
              -- new sum = old sum + newest sample - the sample that falls out of the window
              nx := sum_x + resize(rel_x, SUM_W) - resize(buf_x(WINDOW-1), SUM_W);
              ny := sum_y + resize(rel_y, SUM_W) - resize(buf_y(WINDOW-1), SUM_W);
              sum_x <= nx;
              sum_y <= ny;
              buf_x(1 to WINDOW-1) <= buf_x(0 to WINDOW-2);   -- shift the history by one
              buf_y(1 to WINDOW-1) <= buf_y(0 to WINDOW-2);
              buf_x(0) <= rel_x;
              buf_y(0) <= rel_y;
              if abs(nx) + abs(ny) > to_signed(THRESHOLD, SUM_W) then
                state <= ST_DEPLOYED;
              end if;
            end if;

          when ST_DEPLOYED =>
            null;                                -- stays deployed until reset
        end case;
      end if;
    end if;
  end process;
end architecture;