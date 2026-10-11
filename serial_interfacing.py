import serial, time

s = serial.Serial("/dev/tty.usbserial-101", 115200)
time.sleep(0.5)

# Set 120 BPM (index 4)
s.write(b"B\x04")
time.sleep(0.1)

# Write pattern: kick on 0,4,8,12 — snare on 4,12 — hihat every step
for step in range(16):
    kick = 1 if step % 4 == 0 else 0
    snare = 2 if step % 8 == 4 else 0
    hihat = 4
    mask = kick | snare | hihat
    s.write(bytes([0x57, step, mask]))  # 'W' step mask
    time.sleep(0.05)

# Play
s.write(b"P")
