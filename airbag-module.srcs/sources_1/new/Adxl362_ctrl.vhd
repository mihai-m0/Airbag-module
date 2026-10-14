-- ADXL362 controller
--   1) We read the registers DEVID_AD, DEVID_MST, PARTID (expect AD, 1D, F2) so we can confirm
--   that the sensor has been connected properly
--
--   2) The FILTER_CTL(0x2C) register is meant to set some parameters
--   for our measurements = 0x85 : measurement range -> +/-8 g
--                                 output data rate(ODR) -> 400 Hz
--                                 bandwidth -> 0(ODR/2)
--
--   3) INTMAP1(adrress 0x2A) = 0x01 : DATA_READY on INT1
--   4) POWER_CTL(address 0x2D) = 0x02 : measurement mode (10)
--   5) on every INT1 (data ready): burst-read the following registers:XDATA_L,XDATA_H,...,ZDATA_H (addr 0x0E,..,0x13)
--      If INT1 never comes, fall back to reading every TIMEOUT_CYCLES.
-- ADXL362 commands: 0x0A = write register, 0x0B = read register.
-- for burst reading,we will send 0B,starting_addr,dummy_bytes
-- for wrtiting,we send 0A,addres,value

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adxl362_ctrl is
  generic (
    POWERUP_CYCLES : integer := 2_000_000;   -- 20 ms after being reset
    GUARD_CYCLES   : integer := 1_000;       -- 10 us blind time after a read (lets INT1 clear)
    TIMEOUT_CYCLES : integer := 1_000_000    -- 10 ms fallback if INT1 is silent
  );
  port (
    clk, rst     : in  std_logic;
    spi_start    : out std_logic;
    spi_tx       : out std_logic_vector(7 downto 0);
    spi_rx       : in  std_logic_vector(7 downto 0);
    spi_done     : in  std_logic;
    cs_n         : out std_logic := '1';
    int1         : in  std_logic;            -- data-ready, active high
    id_ok        : out std_logic := '0';
    sample_valid : out std_logic := '0';     -- 1-cycle pulse
    acc_x, acc_y, acc_z : out signed(15 downto 0)
  );
end entity;

architecture rtl of adxl362_ctrl is
  type state_type is (S_POWERUP, S_CS_LOW, S_SEND, S_WAIT, S_CS_HIGH, S_GAP);
  --the state type describes a transaction:the chip select(CS) is pulles low,
  --the bytes are sent,and then it's pulled back high
  type phase_type is (P_ID, P_FILT, P_INT, P_PWR, P_SAMPLE);
  --the phases describe the tasks we will accomplish using this module
  --first we read the IDs,then we set some parameters,set the intmap,set the measurement mode,
  --and then we start burst reading

  signal state : state_type := S_POWERUP;
  signal phase : phase_type := P_ID;
  signal idx   : integer range 0 to 7 := 0;
  signal cnt   : integer range 0 to 2**24-1 := 0;
  signal int1_s1, int1_s : std_logic := '0';

  signal id0, id1, id2 : std_logic_vector(7 downto 0) := (others => '0');
  signal xl, xh, yl, yh, zl, zh : std_logic_vector(7 downto 0) := (others => '0');


  --the purpose of this function is to send the sequence of bytes according to
  --the phase that we're in
  function tx_byte(p : phase_type; i : integer) return std_logic_vector is
  begin
    case p is
      when P_FILT =>                                  --we write 0x85 to reg 0x2C
        if i = 0 then return x"0A";
        elsif i = 1 then return x"2C";
        else return x"85"; end if;
      when P_INT =>                                   -- write 0x01 to reg 0x2A
        if i = 0 then return x"0A";
        elsif i = 1 then return x"2A";
        else return x"01"; end if;
      when P_PWR =>                                   -- write 0x02 to reg 0x2D
        if i = 0 then return x"0A";
        elsif i = 1 then return x"2D";
        else return x"02"; end if;
      when P_ID =>                                    -- read from reg 0x00
        if i = 0 then return x"0B"; else return x"00"; end if;
      when P_SAMPLE =>                                -- burst read from reg 0x0E
        if i = 0 then return x"0B";
        elsif i = 1 then return x"0E";
        else return x"00"; end if;
    end case;
  end function;

  --the purpose of this function is to return the number of bytes
  --we're transactioning during one phase
  function last_idx(p : phase_type) return integer is
  begin
    case p is
      when P_ID     => return 4;   -- cmd, addr, 3 data bytes
      when P_SAMPLE => return 7;   -- cmd, addr, 6 data bytes
      when others   => return 2;   -- cmd, addr, data (register write)
    end case;
  end function;
  
begin
  process(clk)
  begin
    if rising_edge(clk) then
      spi_start    <= '0';
      sample_valid <= '0';
      int1_s1      <= int1;          -- synchronizer
      int1_s       <= int1_s1;

      if rst = '1' then
        state <= S_POWERUP; phase <= P_ID; idx <= 0; cnt <= 0;
        cs_n <= '1'; id_ok <= '0';
      else
        case state is

          when S_POWERUP =>
            if cnt = POWERUP_CYCLES then cnt <= 0; state <= S_CS_LOW;
            else cnt <= cnt + 1; end if;

          --when pulling the CS line low,a transaction starts
          when S_CS_LOW =>
            cs_n  <= '0';
            idx   <= 0;
            state <= S_SEND;

          --spi_tx holds the byte we will send
          --idx is the index of the byte we're sending
          when S_SEND =>
            spi_tx    <= tx_byte(phase, idx);
            spi_start <= '1';
            state     <= S_WAIT;

          
          when S_WAIT =>
            if spi_done = '1' then
              case phase is
              --the first 2 bytes which are sent back are ignored
                when P_ID =>
                  if    idx = 2 then id0 <= spi_rx;
                  elsif idx = 3 then id1 <= spi_rx;
                  elsif idx = 4 then id2 <= spi_rx; end if;
                  
                when P_SAMPLE =>
                  case idx is
                    when 2 => xl <= spi_rx;
                    when 3 => xh <= spi_rx;
                    when 4 => yl <= spi_rx;
                    when 5 => yh <= spi_rx;
                    when 6 => zl <= spi_rx;
                    when 7 => zh <= spi_rx;
                    when others => null;
                  end case;
                when others => null;
              end case;

              if idx = last_idx(phase) then
                state <= S_CS_HIGH;
              else
                idx   <= idx + 1;
                state <= S_SEND;
              end if;
            end if;

          when S_CS_HIGH =>
            cs_n  <= '1';
            cnt   <= 0;
            state <= S_GAP;
            case phase is
              when P_ID =>
                if id0 = x"AD" and id1 = x"1D" and id2 = x"F2" then
                  id_ok <= '1';
                else
                  id_ok <= '0';
                end if;
                phase <= P_FILT;
              when P_FILT => phase <= P_INT;
              when P_INT  => phase <= P_PWR;
              when P_PWR  => phase <= P_SAMPLE;
              when P_SAMPLE =>
                acc_x <= signed(xh & xl);
                acc_y <= signed(yh & yl);
                acc_z <= signed(zh & zl);
                sample_valid <= '1';
            end case;

          when S_GAP =>
            if phase = P_SAMPLE then
              -- wait for data-ready(after a short guard time), or time out
              if cnt >= GUARD_CYCLES and (int1_s = '1' or cnt = TIMEOUT_CYCLES) then
                cnt   <= 0;
                state <= S_CS_LOW;
              elsif cnt < TIMEOUT_CYCLES then
                cnt <= cnt + 1;
              end if;
            else
              if cnt = 100 then cnt <= 0; state <= S_CS_LOW;
              else cnt <= cnt + 1; end if;
            end if;

        end case;
      end if;
    end if;
  end process;
end architecture;