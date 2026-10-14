# Live plot + CSV logger for the ADXL362 stream.
#   pip install pyserial matplotlib
#   Close PuTTY first. Edit PORT below, run:  python live_plot.py
#   Keys in the plot window:  z = zero (subtract the current resting average)
#                             r = remove the zero again
#   Closing the window saves everything to log_YYYYmmdd_HHMMSS.csv
import csv, struct, time
from collections import deque
import serial
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation

PORT      = "COM7"
BAUD      = 115200
LSB_PER_G = 250.0      # +/-8 g range: 4 mg per LSB
FS        = 400.0      # sample rate in Hz (ODR set in the FPGA)
WINDOW_S  = 5          # seconds shown on screen
YLIM      = 4.0        # plot range in g (+/-)

buf = bytearray()
log = []                                   # (sample_no, x_lsb, y_lsb, z_lsb)
n = 0
win = {k: deque([0.0] * int(FS * WINDOW_S), maxlen=int(FS * WINDOW_S)) for k in "xyz"}
offset = [0.0, 0.0, 0.0]

def parse(buf):
    """Pull complete 7-byte frames out of buf. Resync on 0xAA if bytes are lost."""
    frames = []
    while len(buf) >= 7:
        if buf[0] != 0xAA:
            del buf[0]; continue
        x, y, z = struct.unpack(">hhh", bytes(buf[1:7]))
        if all(-2048 <= v <= 2047 for v in (x, y, z)):
            frames.append((x, y, z)); del buf[:7]
        else:
            del buf[0]                      # false header, slide by one byte
    return frames

ser = serial.Serial(PORT, BAUD, timeout=0)
fig, ax = plt.subplots()
t = [i / FS - WINDOW_S for i in range(int(FS * WINDOW_S))]
lines = {k: ax.plot(t, list(win[k]), label=k.upper())[0] for k in "xyz"}
ax.set_ylim(-YLIM, YLIM); ax.set_xlim(-WINDOW_S, 0)
ax.set_xlabel("time (s)"); ax.set_ylabel("acceleration (g)")
ax.grid(True); ax.legend(loc="upper left")

def update(_):
    global n
    buf.extend(ser.read(ser.in_waiting or 1))
    for x, y, z in parse(buf):
        n += 1
        log.append((n, x, y, z))
        for k, v, o in zip("xyz", (x, y, z), offset):
            win[k].append(v / LSB_PER_G - o)
    for k in "xyz":
        lines[k].set_ydata(list(win[k]))
    return lines.values()

def on_key(e):
    if e.key == "z" and len(log) >= 100:
        last = log[-100:]
        for i in range(3):
            offset[i] = sum(r[i + 1] for r in last) / len(last) / LSB_PER_G
        print("zeroed, offsets (g):", [round(o, 3) for o in offset])
    elif e.key == "r":
        offset[:] = [0.0, 0.0, 0.0]

fig.canvas.mpl_connect("key_press_event", on_key)
ani = FuncAnimation(fig, update, interval=40, blit=False, cache_frame_data=False)
plt.show()

ser.close()
name = time.strftime("log_%Y%m%d_%H%M%S.csv")
with open(name, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["sample", "t_s", "x_lsb", "y_lsb", "z_lsb", "x_g", "y_g", "z_g"])
    for k, x, y, z in log:
        w.writerow([k, round(k / FS, 4), x, y, z, x / LSB_PER_G, y / LSB_PER_G, z / LSB_PER_G])
print(f"saved {len(log)} samples to {name}")