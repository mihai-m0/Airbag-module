-- Airbag core = calibrator + crash detector.
-- Raw samples in, "armed" / "deployed" out
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity airbag_core is
  generic (
    LOG2_N    : integer := 6;      -- calibrator: average 2**LOG2_N samples
    SKIP      : integer := 16;     -- calibrator: samples ignored after reset
    WINDOW    : integer := 4;      -- detector: samples added up
    THRESHOLD : integer := 1500    -- detector: threshold in LSB
  );
  port (
    clk, rst     : in  std_logic;
    sample_valid : in  std_logic;
    acc_x, acc_y, acc_z : in signed(15 downto 0);
    calibrated   : out std_logic;
    armed        : out std_logic;
    deployed     : out std_logic;
    rel_valid    : out std_logic;
    rel_x, rel_y, rel_z : out signed(15 downto 0)
  );
end entity;

architecture rtl of airbag_core is
  signal cal_i, rv_i : std_logic;
  signal rx, ry, rz  : signed(15 downto 0);
begin
  u_cal : entity work.calibrator
    generic map (LOG2_N => LOG2_N, SKIP => SKIP)
    port map (clk => clk, rst => rst, sample_valid => sample_valid,
              acc_x => acc_x, acc_y => acc_y, acc_z => acc_z,
              calibrated => cal_i, rel_valid => rv_i,
              rel_x => rx, rel_y => ry, rel_z => rz);

  u_det : entity work.crash_detector
    generic map (WINDOW => WINDOW, THRESHOLD => THRESHOLD)
    port map (clk => clk, rst => rst, calibrated => cal_i, rel_valid => rv_i,
              rel_x => rx, rel_y => ry, armed => armed, deployed => deployed);

  calibrated <= cal_i;
  rel_valid  <= rv_i;
  rel_x <= rx;  rel_y <= ry;  rel_z <= rz;
end architecture;