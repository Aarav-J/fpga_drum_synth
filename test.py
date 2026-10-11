import serial, time

for port in ["/dev/tty.usbserial-100", "/dev/tty.usbserial-101"]:
    print(f"Trying {port}...")
    try:
        s = serial.Serial(port, 115200)
        time.sleep(0.3)
        s.write(b"k")
        time.sleep(1)
        s.close()
        time.sleep(0.5)
    except Exception as e:
        print(f"  failed: {e}")
