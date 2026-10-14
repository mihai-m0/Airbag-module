library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  generic (
    CRASH_WINDOW    : integer := 4;      -- samples added up (4 samples = 10 ms at 400 Hz)
    CRASH_THRESHOLD : integer := 1500    -- in LSB (4 mg each at +/-8 g): 6 g summed over the window
  );
  port (
    CLK100MHZ    : in  std_logic;
    CPU_RESETN   : in  std_logic;                    -- active low button: re-calibrates + clears the latch
    ACL_MISO     : in  std_logic;
    ACL_MOSI     : out std_logic;
    ACL_SCLK     : out std_logic;
    ACL_CSN      : out std_logic;
    ACL_INT1     : in  std_logic;                    -- data-ready from the sensor
    UART_RXD_OUT : out std_logic;                    -- FPGA TX -> PC
    LED          : out std_logic_vector(2 downto 0);
    LED16_R      : out std_logic;                    -- red   = DEPLOYED
    LED16_G      : out std_logic                     -- green = ARMED
  );
end entity;

architecture rtl of top is
  signal rst_s1, rst : std_logic := '1';
  signal spi_start, spi_done : std_logic;
  signal spi_tx, spi_rx      : std_logic_vector(7 downto 0);
  signal id_ok, sample_valid : std_logic;
  signal ax, ay, az          : signed(15 downto 0);
  signal tx_start, tx_busy   : std_logic;
  signal tx_data             : std_logic_vector(7 downto 0);
  signal heartbeat           : std_logic := '0';
  signal int1_seen           : std_logic := '0';
  signal calibrated, armed, deployed, rel_valid : std_logic;
  signal rel_x, rel_y, rel_z : signed(15 downto 0);
begin
  process(CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      rst_s1 <= not CPU_RESETN;
      rst    <= rst_s1;
      if sample_valid = '1' then heartbeat <= not heartbeat; end if;
      if rst = '1' then int1_seen <= '0'; elsif ACL_INT1 = '1' then int1_seen <= '1'; end if;
    end if;
  end process;

  u_spi : entity work.spi_master
    generic map (HALF_PERIOD => 50)
    port map (clk => CLK100MHZ, rst => rst, start => spi_start, tx_data => spi_tx,
              rx_data => spi_rx, done => spi_done,
              sclk => ACL_SCLK, mosi => ACL_MOSI, miso => ACL_MISO);

  u_ctrl : entity work.adxl362_ctrl
    port map (clk => CLK100MHZ, rst => rst, spi_start => spi_start, spi_tx => spi_tx,
              spi_rx => spi_rx, spi_done => spi_done, cs_n => ACL_CSN, int1 => ACL_INT1,
              id_ok => id_ok, sample_valid => sample_valid,
              acc_x => ax, acc_y => ay, acc_z => az);

  -- calibration + crash detection (uses the same samples that are streamed to the PC)
  u_core : entity work.airbag_core
    generic map (LOG2_N => 6, SKIP => 16, WINDOW => CRASH_WINDOW, THRESHOLD => CRASH_THRESHOLD)
    port map (clk => CLK100MHZ, rst => rst, sample_valid => sample_valid,
              acc_x => ax, acc_y => ay, acc_z => az,
              calibrated => calibrated, armed => armed, deployed => deployed,
              rel_valid => rel_valid, rel_x => rel_x, rel_y => rel_y, rel_z => rel_z);

  -- the PC still receives the RAW samples, so recordings stay comparable
  u_str : entity work.sample_streamer
    port map (clk => CLK100MHZ, rst => rst, sample_valid => sample_valid,
              acc_x => ax, acc_y => ay, acc_z => az,
              tx_busy => tx_busy, tx_start => tx_start, tx_data => tx_data);

  u_uart : entity work.uart_tx
    generic map (CLKS_PER_BIT => 868)
    port map (clk => CLK100MHZ, rst => rst, start => tx_start, data => tx_data,
              busy => tx_busy, tx => UART_RXD_OUT);

  LED(0)  <= id_ok;        -- ID registers read correctly
  LED(1)  <= heartbeat;    -- toggles on every sample (400 Hz -> looks steadily lit)
  LED(2)  <= int1_seen;    -- on = sensor's data-ready (INT1) works
  LED16_G <= armed;        -- green: calibrated and watching
  LED16_R <= deployed;     -- red: crash latched
end architecture;