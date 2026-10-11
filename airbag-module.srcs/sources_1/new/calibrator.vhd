-- Calibrator: learns the "resting" value of each axis right after reset
-- and subtracts it from every later sample.
--
--   state S_SETTLE : ignore the first SKIP samples (sensor just switched on)
--   state S_ACCUM  : add up the next 2**LOG2_N samples, per axis
--   state S_DIVIDE : baseline = sum / 2**LOG2_N   (a right shift, no divider needed)
--   state S_RUN    : rel = acc - baseline, for every new sample
--
-- The board must be still while it calibrates (first ~0.2 s after reset).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity calibrator is
  generic (
    LOG2_N : integer := 6;     -- average 2**6 = 64 samples (0.16 s at 400 Hz)
    SKIP   : integer := 16     -- samples ignored after reset (must be >= 1)
  );
  port (
    clk, rst     : in  std_logic;
    sample_valid : in  std_logic;                  -- 1-cycle pulse, new sample on acc_*
    acc_x, acc_y, acc_z : in signed(15 downto 0);  -- raw samples
    calibrated   : out std_logic;                  -- 1 once the baseline is known
    rel_valid    : out std_logic := '0';           -- 1-cycle pulse, rel_* are new
    rel_x, rel_y, rel_z : out signed(15 downto 0) := (others => '0')  -- acc - baseline
  );
end entity;

architecture rtl of calibrator is
  constant W : integer := 16 + LOG2_N;             -- room to add 2**LOG2_N 16-bit values
  type state_t is (S_SETTLE, S_ACCUM, S_DIVIDE, S_RUN);
  signal state : state_t := S_SETTLE;
  signal cnt   : integer range 0 to 2**LOG2_N + SKIP := 0;
  signal sum_x, sum_y, sum_z    : signed(W-1 downto 0)  := (others => '0');
  signal base_x, base_y, base_z : signed(15 downto 0)   := (others => '0');
begin
  calibrated <= '1' when state = S_RUN else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      rel_valid <= '0';                            -- default: pulse is off

      if rst = '1' then
        state <= S_SETTLE;
        cnt   <= 0;
        sum_x <= (others => '0');
        sum_y <= (others => '0');
        sum_z <= (others => '0');
      else
        case state is

          when S_SETTLE =>
            if sample_valid = '1' then
              if cnt = SKIP - 1 then
                cnt   <= 0;
                state <= S_ACCUM;
              else
                cnt <= cnt + 1;
              end if;
            end if;

          when S_ACCUM =>
            if sample_valid = '1' then
              sum_x <= sum_x + resize(acc_x, W);
              sum_y <= sum_y + resize(acc_y, W);
              sum_z <= sum_z + resize(acc_z, W);
              if cnt = 2**LOG2_N - 1 then
                state <= S_DIVIDE;
              else
                cnt <= cnt + 1;
              end if;
            end if;

          when S_DIVIDE =>                         -- the last sample is now in the sums
            base_x <= resize(shift_right(sum_x, LOG2_N), 16);
            base_y <= resize(shift_right(sum_y, LOG2_N), 16);
            base_z <= resize(shift_right(sum_z, LOG2_N), 16);
            cnt    <= 0;
            state  <= S_RUN;

          when S_RUN =>
            if sample_valid = '1' then
              rel_x     <= acc_x - base_x;
              rel_y     <= acc_y - base_y;
              rel_z     <= acc_z - base_z;
              rel_valid <= '1';
            end if;

        end case;
      end if;
    end if;
  end process;
end architecture;