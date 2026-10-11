# FPGA Crash Detection Module (Airbag Demo)

## About the project

This project is a crash detector built in VHDL for the **Digilent Nexys A7-100T** FPGA board. The idea is to imitate, on a small scale, what the control unit of a car airbag does: continuously read an acceleration sensor, work out whether a sudden deceleration (a crash) has happened, and trigger an output when it does. Here the output is an LED, so nothing in this project controls a real airbag.

The design reads the accelerometer that is already on the board, so no extra hardware is needed. Everything is written from scratch in VHDL, without vendor IP cores or a soft-core processor: the SPI communication, the sensor setup, the UART link to the PC, the calibration and the crash detection.

The project is **still under development**. The sensor reading and the live plotting work on the board. The crash-detection logic is written and verified in simulation, and still has to be tuned and tested on the board (see the roadmap at the end).

## The sensor: ADXL362

The ADXL362 is a 3-axis digital accelerometer from Analog Devices, soldered on the Nexys A7. The main facts relevant here:

- It measures acceleration on three axes (X, Y, Z) and is read over **SPI**. It supports SPI mode 0, and this project clocks it at 1 MHz.
- It has selectable ranges of 2 g, 4 g and 8 g, and output rates from 12.5 Hz up to 400 Hz. This design uses **8 g and 400 Hz**, so a short, strong impact still fits in the range.
- Each reading is a 12-bit signed number, delivered in two bytes per axis. At 8 g, one step (LSB) is 4 mg.
- At rest the sensor does not read zero. It measures the force that holds it against gravity, so a board lying flat reads about 1 g on the vertical axis. A crash shows up as a short, strong change on top of that, which is why the design calibrates a resting baseline first.
- It can raise a **data-ready** signal on its INT1 pin each time a new sample is available. The design uses it to read exactly one sample per measurement.
- After power-up it is in standby, so it has to be configured and switched to measurement mode with register writes.

## Repository layout

```
rtl/           VHDL design files
tb/            self-checking testbenches
constraints/   pin assignments for the Nexys A7-100T
python/        scripts for the PC side
scripts/       Vivado project creation script
```

## The design files (`rtl/`)

Data flows through the modules in this order:

```
ADXL362 <--SPI--> spi_master <--> adxl362_ctrl --+--> sample_streamer --> uart_tx --> PC
                                                 |
                                                 +--> airbag_core (calibrator --> crash_detector) --> LEDs
```

**`spi_master.vhd`** is the lowest layer. It sends and receives one byte over SPI (mode 0, MSB first) and drives the SCLK and MOSI lines while sampling MISO. It knows nothing about the sensor: it gets a byte and a `start` pulse, and reports the received byte with a `done` pulse. Chip select is handled by the controller above it.

**`adxl362_ctrl.vhd`** knows the sensor's language. It uses the SPI master to check the sensor ID, configure the sensor, and then read the X, Y and Z values every time the sensor signals that new data is ready. It outputs the three readings as signed 16-bit numbers with a `sample_valid` pulse, and an `id_ok` flag. Its structure is explained in the next section.

**`sample_streamer.vhd`** packs each sample into a 7-byte frame (`0xAA`, then X, Y and Z as 16-bit values, high byte first) and hands the bytes to the UART one by one. The header byte lets the PC find the start of a frame, even if some bytes were lost.

**`uart_tx.vhd`** is a UART transmitter (115200 baud, 8 data bits, no parity, 1 stop bit). It turns each byte into the serial bit sequence and sends it through the board's USB-UART bridge to the PC.

**`calibrator.vhd`** removes the resting values from the readings. After reset it ignores a few samples, averages the next 64 per axis, and from then on outputs each sample minus that baseline. This takes out gravity and the sensor's own offset, so a board at rest reads close to zero on all axes. The board has to be still for roughly the first quarter of a second after reset.

**`crash_detector.vhd`** makes the decision. It is a small state machine: it waits for the calibration, then is *armed* and compares each calibrated sample on the chosen axis with a threshold. The direction is configurable, so only a deceleration in the crash direction counts, and starting to move in the opposite direction does not. When the threshold is exceeded it goes to *deployed* and stays there until reset, like a real airbag.

**`airbag_core.vhd`** connects the calibrator and the crash detector and selects which axis is used for detection.

**`top.vhd`** is the top level. It connects all the modules, synchronizes the reset button, and drives the LEDs: LED0 shows the sensor ID was read correctly, LED2 shows the data-ready signal was seen, and the RGB LED16 shows the detector state (green = armed, red = crash detected). The detection threshold, the axis and the direction are generics at the top of this file.

**`constraints/nexys_a7.xdc`** assigns the signals to the physical pins of the board (clock, reset button, accelerometer, UART, LEDs).

**`tb/`** holds self-checking testbenches for the calibrator, the crash detector and the full core. They contain `assert` statements and print `ALL TESTS PASSED` when everything behaves as expected.

## How the sensor controller works: phases and states

`adxl362_ctrl.vhd` is organised on two levels.

A **phase** says *which SPI transaction* is being carried out. The controller goes through the phases in order, and then stays in the last one:

| Phase | Bytes sent | Purpose |
|---|---|---|
| `P_ID` | `0B 00` + 3 reads | read the three ID registers, expecting `AD`, `1D`, `F2` |
| `P_FILT` | `0A 2C 85` | write `FILTER_CTL`: 8 g range, 400 Hz output rate |
| `P_INT` | `0A 2A 01` | write `INTMAP1`: data-ready signal on INT1 |
| `P_PWR` | `0A 2D 02` | write `POWER_CTL`: switch to measurement mode |
| `P_SAMPLE` | `0B 0E` + 6 reads | read X, Y and Z (registers `0x0E` to `0x13`), repeatedly |

`0x0A` is the sensor's write command and `0x0B` is the read command. After the command comes the register address, and then the data.

A **state** says *which step of a transaction* the controller is in. The same six states run for every phase:

| State | What it does |
|---|---|
| `S_POWERUP` | waits about 20 ms after reset before talking to the sensor |
| `S_CS_LOW` | pulls chip select low to start a transaction |
| `S_SEND` | loads the next byte and tells the SPI master to send it |
| `S_WAIT` | waits for the byte to finish, stores the received byte, then goes back to `S_SEND` or ends the transaction |
| `S_CS_HIGH` | releases chip select, finishes the transaction and moves on to the next phase |
| `S_GAP` | waits before the next transaction. In the sampling phase it waits for the sensor's data-ready signal, with a 10 ms timeout as a fallback |

## Python scripts (`python/`)

**`live_plot.py`** lets you read and watch the live sensor data on your PC. It receives the frames from the board over the serial port and plots X, Y and Z in a scrolling window. Pressing `z` in the plot window subtracts the current resting values, so you can see only the movement, and closing the window saves everything to a CSV file.

To use it:

1. Program the board, then close any other program that uses the serial port (for example PuTTY).
2. Install the dependencies: `pip install pyserial matplotlib`
3. Open `live_plot.py` and set `PORT` to the COM port of the board (visible in Device Manager).
4. Run `python live_plot.py`.

The other scripts are small helpers: `read_xyz.py` prints the values as text, `plot_csv.py` plots a saved CSV, and `summarize_csv.py` lists the spikes found in a CSV (time, peak and duration).

## Building the project

1. In Vivado, run `source scripts/create_project.tcl` from the repository folder. It creates a project for the Nexys A7-100T with all the files. Alternatively, create the project manually for the part `xc7a100tcsg324-1`, add the files from `rtl/` and `constraints/`, and set `top` as the top module.
2. Generate the bitstream and program the board.
3. Keep the board still for about a quarter of a second after programming or after pressing the reset button. The CPU reset button recalibrates and clears the crash latch.

## Roadmap

This project is a work in progress. Where it stands:

- [x] SPI master and sensor controller (sensor ID read, configuration, X/Y/Z readout)
- [x] UART streaming to the PC and live plotting in Python
- [x] Calibrator, crash detector and their testbenches (verified in simulation)
- [ ] Test the calibrator and crash detector on the board
- [ ] Record data for different events (crashes, taps, drops, shaking) and choose the threshold, the crash axis and the direction from it
- [ ] Reject false triggers, for example by requiring several consecutive samples above the threshold, or by integrating the change in velocity over a short window
- [ ] Measure the detection latency and the false-trigger rate
- [ ] Add screenshots of the live plot and a short demo video

The detection threshold, the axis and the direction currently in `top.vhd` are placeholders and will change once there is recorded data to base them on.
