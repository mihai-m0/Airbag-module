-- Self-checking testbench for crash_detector.vhd (WINDOW = 4, THRESHOLD = 1500 LSB; 1 g = 250 LSB).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_crash_detector is end entity;

architecture sim of tb_crash_detector is
  signal clk        : std_logic := '0';
  signal done       : boolean   := false;
  signal rst        : std_logic := '1';
  signal calibrated, rel_valid : std_logic := '0';
  signal rx, ry     : signed(15 downto 0) := (others => '0');
  signal armed, deployed : std_logic;
begin
  clk <= not clk after 5 ns when not done;

  dut : entity work.crash_detector
    generic map (WINDOW => 4, THRESHOLD => 1500)
    port map (clk => clk, rst => rst, calibrated => calibrated, rel_valid => rel_valid,
              rel_x => rx, rel_y => ry, armed => armed, deployed => deployed);

  stim : process
    procedure wait_clk(n : integer) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure send(x, y : integer) is          -- one calibrated sample, then a few idle cycles
    begin
      wait until rising_edge(clk);
      rx <= to_signed(x, 16); ry <= to_signed(y, 16); rel_valid <= '1';
      wait until rising_edge(clk);
      rel_valid <= '0';
      wait_clk(3);
    end procedure;

    procedure send_n(n, x, y : integer) is
    begin
      for i in 1 to n loop send(x, y); end loop;
    end procedure;

    procedure restart is                       -- reset, then calibration "done" again
    begin
      calibrated <= '0'; rst <= '1'; wait_clk(3);
      rst <= '0'; calibrated <= '1'; wait_clk(3);
      assert armed = '1' and deployed = '0' report "not armed after restart" severity failure;
    end procedure;
  begin
    wait for 100 ns;
    rst <= '0';

    -- 1) before calibration: huge samples must be ignored
    send_n(4, 2000, 2000);
    assert deployed = '0' and armed = '0' report "reacted before calibration" severity failure;

    -- 2) rest noise
    restart;
    for i in 1 to 10 loop send(2, -2); send(-2, 2); end loop;
    assert deployed = '0' report "false deploy on noise" severity failure;

    -- 3) the gentle push at the start of a slide: 0.4 g (100 LSB) for 130 ms (52 samples)
    send_n(52, 100, 0);
    assert deployed = '0' report "false deploy on a slow push" severity failure;

    -- 4) taps: 2 g (500 LSB) for 2 samples, on X and on Y
    restart;
    send_n(2, 500, 0);  send_n(6, 0, 0);
    send_n(2, 0, -500); send_n(6, 0, 0);
    assert deployed = '0' report "false deploy on a tap" severity failure;

    -- 5) two separate bursts: each adds up to 800, and old samples must leave the window
    send_n(2, 400, 0);  send_n(6, 0, 0);
    send_n(2, 400, 0);  send_n(6, 0, 0);
    assert deployed = '0' report "window does not forget old samples" severity failure;

    -- 6) exactly at the threshold: not "above"; one LSB more: deploy
    restart;
    send_n(4, 375, 0);                         -- sum = 1500
    assert deployed = '0' report "deployed at exactly the threshold" severity failure;
    send_n(4, 0, 0);                           -- flush the window
    send_n(3, 375, 0);
    assert deployed = '0' report "deployed too early" severity failure;
    send(376, 0);                              -- sum = 1501
    assert deployed = '1' and armed = '0' report "did not deploy just above threshold" severity failure;

    -- 7) latched: calm samples must not release it
    send_n(5, 0, 0);
    assert deployed = '1' report "latch released by itself" severity failure;

    -- 8) direction does not matter: negative X
    restart;
    send_n(4, -400, 0);
    assert deployed = '1' report "negative X crash not detected" severity failure;

    -- 9) X and Y add up (absolute values), even with opposite signs
    restart;
    send_n(3, 250, -250);                      -- 750 + 750 = 1500: not above
    assert deployed = '0' report "deployed at exactly the threshold (X+Y)" severity failure;
    send(250, -250);                           -- 1000 + 1000 = 2000
    assert deployed = '1' report "X+Y crash not detected" severity failure;

    -- 10) reset releases the latch
    calibrated <= '0'; rst <= '1'; wait_clk(3);
    rst <= '0'; wait_clk(3);
    assert deployed = '0' and armed = '0' report "reset did not clear" severity failure;

    report "ALL TESTS PASSED";
    done <= true;
    wait;
  end process;
end architecture;