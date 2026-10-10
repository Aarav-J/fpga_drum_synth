import math

with open("src/sine_table.hex", "w") as f:
    for i in range(256):
        val = round(26214 * math.sin(2 * math.pi * i / 256))  # 80% of 32767
        if val < 0:
            val = val + 65536
        f.write(f"{val:04X}\n")
