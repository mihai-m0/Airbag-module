-- Self-checking testbench for calibrator.vhd (small generics so it runs fast):
--   SKIP = 4 samples ignored, then 8 rest samples averaged (LOG2_N = 3).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_calibrator is end entity;

architecture sim of tb_calibrator is
  constant LOG2_N : integer := 3;
  constant SKIP   : integer := 4;

  signal clk          : std_logic := '0';
  signal done         : boolean   := false;
  signal rst          : std_logic := '1';
  signal sample_valid : std_logic := '0';
  signal ax, ay, az   : signed(15 downto 0) := (others => '0');
  signal calibrated, rel_valid : std_logic;
  signal rx, ry, rz   : signed(15 downto 0);
  signal valid_count  : integer := 0;

  type int_arr is array (0 to 7) of integer;
  constant noise : int_arr := (1, -1, 2, -2, 0, 0, 1, -1);   -- sums to 0
begin
  clk <= not clk after 5 ns when not done;         -- clock stops when the test ends

  dut : entity work.calibrator
    generic map (LOG2_N => LOG2_N, SKIP => SKIP)
    port map (clk => clk, rst => rst, sample_valid => sample_valid,
              acc_x => ax, acc_y => ay, acc_z => az,
              calibrated => calibrated, rel_valid => rel_valid,
              rel_x => rx, rel_y => ry, rel_z => rz);

  -- counts how many rel_valid pulses the DUT produces
  process(clk) begin
    if rising_edge(clk) and rel_valid = '1' then valid_count <= valid_count + 1; end if;
  end process;

  stim : process
    -- present one sample (1-cycle sample_valid pulse), then idle 10 cycles
    procedure send(x, y, z : integer) is
    begin
      wait until rising_edge(clk);
      ax <= to_signed(x, 16); ay <= to_signed(y, 16); az <= to_signed(z, 16);
      sample_valid <= '1';
      wait until rising_edge(clk);
      sample_valid <= '0';
      for i in 1 to 10 loop wait until rising_edge(clk); end loop;
    end procedure;
  begin
    wait for 100 ns;
    rst <= '0';

    -- 1) settling samples: wild values that must be ignored
    for i in 1 to SKIP loop
      send(500, -500, 500);
      assert calibrated = '0' report "calibrated too early (settle)" severity failure;
    end loop;

    -- 2) rest samples around X=-11, Y=-2, Z=-185 (noise averages to exactly 0)
    for i in 0 to 7 loop
      send(-11 + noise(i), -2 - noise(i), -185 + noise(i));
      if i < 7 then
        assert calibrated = '0' report "calibrated too early (accumulate)" severity failure;
      end if;
    end loop;
    assert calibrated = '1'   report "should be calibrated now" severity failure;
    assert valid_count = 0    report "rel_valid fired during calibration" severity failure;

    -- 3) resting sample -> everything 0
    send(-11, -2, -185);
    assert rx = 0 and ry = 0 and rz = 0 report "rest sample not zero" severity failure;

    -- 4) "crash": X drops by 100 LSB
    send(-111, -2, -185);
    assert rx = -100 and ry = 0 and rz = 0 report "X step wrong" severity failure;

    -- 5) Y up 50, Z up 250 (1 g at +/-8 g)
    send(-11, 48, 65);
    assert rx = 0 and ry = 50 and rz = 250 report "Y/Z step wrong" severity failure;

    assert valid_count = 3 report "wrong number of rel_valid pulses" severity failure;
    report "ALL TESTS PASSED";
    done <= true;
    wait;
  end process;
end architecture;