-- Self-checking testbench for airbag_core.vhd: raw samples in, deployed out.
-- Small calibrator generics (SKIP=4, 8-sample average); detector WINDOW=4, THRESHOLD=1500 LSB.
-- Time is compressed: samples are 12 clock cycles apart, not 2.5 ms.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_airbag_core is end entity;

architecture sim of tb_airbag_core is
  signal clk  : std_logic := '0';
  signal done : boolean   := false;
  signal rst  : std_logic := '1';
  signal sample_valid : std_logic := '0';
  signal ax, ay, az : signed(15 downto 0) := (others => '0');
  signal calibrated, armed, deployed, rel_valid : std_logic;
  signal rx, ry, rz : signed(15 downto 0);

  type int_arr is array (0 to 7) of integer;
  constant noise : int_arr := (1, -1, 2, -2, 0, 0, 1, -1);   -- sums to 0
begin
  clk <= not clk after 5 ns when not done;

  dut : entity work.airbag_core
    generic map (LOG2_N => 3, SKIP => 4, WINDOW => 4, THRESHOLD => 1500)
    port map (clk => clk, rst => rst, sample_valid => sample_valid,
              acc_x => ax, acc_y => ay, acc_z => az,
              calibrated => calibrated, armed => armed, deployed => deployed,
              rel_valid => rel_valid, rel_x => rx, rel_y => ry, rel_z => rz);

  stim : process
    procedure send(x, y, z : integer) is
    begin
      wait until rising_edge(clk);
      ax <= to_signed(x, 16); ay <= to_signed(y, 16); az <= to_signed(z, 16);
      sample_valid <= '1';
      wait until rising_edge(clk);
      sample_valid <= '0';
      for i in 1 to 10 loop wait until rising_edge(clk); end loop;
    end procedure;

    -- power-up sequence: SKIP wild samples, then 8 rest samples around (bx, by, bz)
    procedure calibrate(bx, by, bz : integer) is
    begin
      for i in 1 to 4 loop send(500, -500, 500); end loop;
      for i in 0 to 7 loop send(bx + noise(i), by - noise(i), bz + noise(i)); end loop;
    end procedure;
  begin
    wait for 100 ns;
    rst <= '0';

    -- 1) board at rest on the desk (X=-11, Y=-2, Z=-185 LSB, like a real offset board)
    calibrate(-11, -2, -185);
    assert calibrated = '1' and armed = '1' report "not armed after calibration" severity failure;

    -- 2) 24 noisy rest samples: nothing happens
    for i in 0 to 23 loop send(-11 + noise(i mod 8), -2, -185 + noise(i mod 8)); end loop;
    assert deployed = '0' report "false deploy at rest" severity failure;

    -- 3) start of a slide: gentle push, +100 LSB (0.4 g) on X for 52 samples
    for i in 1 to 52 loop send(-11 + 100, -2, -185); end loop;
    assert deployed = '0' report "false deploy when starting to move" severity failure;
    for i in 1 to 8 loop send(-11, -2, -185); end loop;

    -- 4) a violent movement on Z only (+2000 LSB for 4 samples): Z is not used
    for i in 1 to 4 loop send(-11, -2, -185 + 2000); end loop;
    assert deployed = '0' report "false deploy from a Z bump" severity failure;
    for i in 1 to 8 loop send(-11, -2, -185); end loop;

    -- 5) the crash: X drops by 400 LSB (1.6 g) for 4 samples
    for i in 1 to 4 loop send(-11 - 400, -2, -185); end loop;
    assert deployed = '1' report "crash not detected" severity failure;

    -- 6) back at rest: stays deployed
    for i in 0 to 5 loop send(-11, -2, -185); end loop;
    assert deployed = '1' report "latch released" severity failure;

    -- 7) reset, board now resting at X=-600. With the OLD baseline rel_x would be -589
    --    (4 samples add up to 2356 > 1500) and trigger. It must recalibrate instead.
    rst <= '1';
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    assert deployed = '0' and calibrated = '0' report "reset did not clear" severity failure;
    calibrate(-600, -2, -185);
    assert armed = '1' and deployed = '0' report "recalibration failed" severity failure;
    for i in 1 to 8 loop send(-600, -2, -185); end loop;
    assert deployed = '0' report "used the old baseline" severity failure;

    -- 8) and it still detects a crash, now in the +Y direction
    for i in 1 to 4 loop send(-600, -2 + 400, -185); end loop;
    assert deployed = '1' report "crash after recalibration not detected" severity failure;

    report "ALL TESTS PASSED";
    done <= true;
    wait;
  end process;
end architecture;