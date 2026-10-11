"""Synchronous, write-only UART control for the Tang Nano9K drum machine.

Successful writes mean the host sent the command, not that the FPGA acknowledged
it: this protocol has no acknowledgments. The GUI owns its displayed pattern.
"""

import serial


BPMS = (60, 70, 80, 100, 120, 140, 160, 180)
NOTES = ("C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5")


class DrumConnectionError(ConnectionError):
    """The serial port could not be opened or is not connected."""


class DrumWriteError(OSError):
    """A command could not be completely written; the port has been closed."""


def _integer_in_range(value, name, minimum, maximum):
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError(f"{name} must be an integer")
    if not minimum <= value <= maximum:
        raise ValueError(f"{name} must be between {minimum} and {maximum}")
    return value


def _bpm_index(bpm):
    _integer_in_range(bpm, "bpm", BPMS[0], BPMS[-1])
    if bpm not in BPMS:
        raise ValueError(f"bpm must be one of {BPMS}")
    return BPMS.index(bpm)


class DrumController:
    """Own one explicitly selected serial port without probing or background work.

    Connecting deliberately clears the board, pauses playback, mutes the DDS
    tone, selects C4, and sets 120 BPM. Upload the GUI's local pattern afterward
    if it should be restored. A failed write drops the connection because a
    partially transmitted command leaves the FPGA parser state unknown.
    """

    _TRIGGERS = {"kick": b"k", "snare": b"s", "closed": b"h", "open": b"H"}

    def __init__(self):
        self._serial = None

    @property
    def port(self):
        """The selected port name, or None when disconnected."""
        return self._serial.port if self.connected else None

    @property
    def connected(self):
        return self._serial is not None and self._serial.is_open

    def connect(self, port):
        if not isinstance(port, str):
            raise TypeError("port must be a string")
        if not port.strip():
            raise ValueError("port must not be empty")

        self.disconnect()
        try:
            self._serial = serial.Serial(
                port, 115200, timeout=0, write_timeout=0.5
            )
        except Exception as exc:
            self._close()
            raise DrumConnectionError(f"Could not open serial port {port!r}: {exc}") from exc

        # At most two pending data bytes precede the next command. Three C
        # bytes therefore reach idle and clear even from a partial W packet.
        # Keep the synchronization and explicit defaults in one contiguous write.
        self._write(b"CCCqT\x00N\x00B\x04")

    def _close(self):
        connection = self._serial
        self._serial = None
        if connection is not None:
            try:
                connection.close()
            except Exception:
                # Never mask the original failure or leave a stale connection.
                pass

    def disconnect(self):
        """Best-effort pause/mute, then close; safe to call repeatedly."""
        connection = self._serial
        try:
            if connection is not None and connection.is_open:
                connection.write(b"qT\x00")
        except Exception:
            # Unplugged or failed devices must still release their host handle.
            pass
        finally:
            self._close()

    def _write(self, packet):
        if not self.connected:
            self._close()
            raise DrumConnectionError("No serial port is connected")
        try:
            written = self._serial.write(packet)
            if written != len(packet):
                raise DrumWriteError(
                    f"Incomplete serial write: sent {written!r} of {len(packet)} bytes"
                )
        except Exception as exc:
            self._close()
            if isinstance(exc, DrumWriteError):
                raise
            raise DrumWriteError(f"Could not write serial command: {exc}") from exc

    def set_step(self, step, mask):
        step = _integer_in_range(step, "step", 0, 15)
        mask = _integer_in_range(mask, "mask", 0, 15)
        self._write(bytes((ord("W"), step, mask)))

    def upload_pattern(self, masks, bpm):
        """Validate the complete pattern, then send all 16 steps and its BPM."""
        bpm_index = _bpm_index(bpm)
        try:
            steps = tuple(masks)
        except TypeError as exc:
            raise TypeError("masks must be an iterable of 16 integer masks") from exc
        if len(steps) != 16:
            raise ValueError("masks must contain exactly 16 steps")
        for step, mask in enumerate(steps):
            _integer_in_range(mask, f"mask at step {step}", 0, 15)

        packet = bytearray()
        for step, mask in enumerate(steps):
            packet.extend((ord("W"), step, mask))
        packet.extend((ord("B"), bpm_index))
        self._write(packet)

    def clear(self):
        self._write(b"C")

    def set_bpm(self, bpm):
        self._write(bytes((ord("B"), _bpm_index(bpm))))

    def set_volume(self, percent):
        """Set master amplitude from 0 to 200 percent (0 mutes).

        100 percent is the original mixer level; 200 preserves the boosted
        output. Send V followed by gain 0..128, with 64 representing 100
        percent and integer half-up rounding: (percent * 64 + 50) // 100.
        """
        percent = _integer_in_range(percent, "percent", 0, 200)
        gain = (percent * 64 + 50) // 100
        self._write(bytes((ord("V"), gain)))

    def play(self):
        self._write(b"p")

    def pause(self):
        self._write(b"q")

    def trigger(self, voice):
        if not isinstance(voice, str):
            raise TypeError("voice must be a string")
        if voice not in self._TRIGGERS:
            raise ValueError("voice must be kick, snare, closed, or open")
        self._write(self._TRIGGERS[voice])

    def set_note(self, index):
        index = _integer_in_range(index, "note index", 0, len(NOTES) - 1)
        self._write(bytes((ord("N"), index)))

    def set_tone(self, enabled):
        if not isinstance(enabled, (bool, int)):
            raise TypeError("enabled must be a boolean or integer 0 or 1")
        if enabled not in (0, 1):
            raise ValueError("enabled must be 0 or 1")
        self._write(bytes((ord("T"), int(enabled))))
