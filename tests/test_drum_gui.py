"""Run: python3 -m unittest discover -s tests -p 'test_drum_gui.py'.
Uses a real Tk window and OS pseudo-terminal, not a mocked serial connection.
"""
import os
import select
import tkinter as tk
import unittest

from drum_gui import DrumApp
from drum_control import BPMS, DrumController


class GuiSerialTests(unittest.TestCase):
    def setUp(self):
        self.master, self.slave = os.openpty()
        self.root = tk.Tk()
        self.app = DrumApp(self.root)
        self.root.update()
        self.app.port.set(os.ttyname(self.slave))

    def tearDown(self):
        self.app.close()
        os.close(self.master)
        os.close(self.slave)

    def received(self):
        data = bytearray()
        while select.select([self.master], [], [], 0.1)[0]:
            data.extend(os.read(self.master, 4096))
        return bytes(data)

    def connect(self):
        self.app.connect()
        self.root.update()
        self.assertTrue(self.app.controller.connected)
        packet = self.received()
        self.assertEqual(packet[:10], b"CCCqT\x00N\x00B\x04")
        self.assertEqual(packet[10:], self.pattern_packet() + b"V\x80")

    def pattern_packet(self):
        return b"".join(bytes((ord("W"), i, mask)) for i, mask in enumerate(self.app.pattern)) + bytes((ord("B"), BPMS.index(int(self.app.bpm.get()))))

    def test_grid_transport_and_notes(self):
        self.connect()
        self.app.cells[3][0].invoke()
        self.assertEqual(self.app.pattern[0], 9)
        self.assertEqual(self.received(), b"W\x00\x09")
        self.app.cells[2][0].invoke()
        self.assertEqual(self.app.pattern[0], 5)
        self.assertEqual(self.received(), b"W\x00\x05")
        self.app.play()
        self.app.play()
        self.app.pause()
        self.app.pause()
        self.assertEqual(self.received(), b"ppqq")
        self.app.press_note(7, "test")
        self.assertEqual(self.received(), b"N\x07T\x01")
        self.assertEqual(self.app.note, 7)
        self.assertFalse(self.app.tone.get())
        self.app.release_note("test")
        for voice in ("kick", "snare", "closed", "open"):
            self.app.trigger(voice)
        self.assertEqual(self.received(), b"T\x00kshH")
        self.app.bpm.set("180")
        self.app.change_bpm()
        self.assertEqual(self.received(), b"B\x07")
        self.app.clear_pattern()
        self.assertEqual(self.received(), b"C")
        self.assertEqual(self.app.pattern, [0] * 16)
        self.app.preset("Four on the floor")
        self.assertEqual(self.received(), self.pattern_packet())
        self.app.connect()
        self.assertFalse(self.app.controller.connected)
        self.assertEqual(self.received(), b"qT\x00")
        self.assertEqual(str(self.app.note_buttons[0]["state"]), "disabled")

    def test_disconnected_editor_and_connection_error(self):
        self.assertEqual(str(self.app.volume_scale["state"]), "normal")
        self.app.volume_scale.set(75)
        self.root.update()
        self.assertEqual(self.app.volume.get(), 75)
        self.assertIn("75%", self.app.volume_label.get())
        self.assertIsNone(self.app.volume_after)
        self.app.cells[0][1].invoke()
        self.assertEqual(self.app.pattern[1], 5)
        self.assertEqual(self.received(), b"")
        self.app.port.set("/dev/hardbeat-does-not-exist")
        self.app.connect()
        self.assertFalse(self.app.controller.connected)
        self.assertIn("Cannot connect", self.app.status.get())

    def test_held_note_priority_repeat_and_latch(self):
        self.connect()
        self.app.press_note(0, "key:1")
        self.app.press_note(0, "key:1")
        self.app.press_note(2, "key:3")
        self.app.release_note("key:3")
        self.app.release_note("key:1")
        self.assertEqual(self.received(), b"N\x00T\x01N\x02T\x01N\x00T\x00")
        self.app.tone.set(True)
        self.app.change_tone()
        self.app.press_note(5, "mouse")
        self.app.release_note("mouse")
        self.assertEqual(self.received(), b"T\x01N\x05T\x01")
        self.app.tone.set(False)
        self.app.change_tone()
        self.assertEqual(self.received(), b"T\x00")

    def test_master_amplitude_slider(self):
        self.connect()
        # Drag changes are coalesced; only the last requested gain is sent.
        self.app.change_volume("25")
        self.app.change_volume("100")
        self.root.after(120, self.root.quit)
        self.root.mainloop()
        self.assertEqual(self.received(), b"V\x40")
        for percent, gain in ((0, 0), (1, 1), (50, 32), (200, 128)):
            self.app.controller.set_volume(percent)
            self.assertEqual(self.received(), bytes((ord("V"), gain)))

    def test_controller_rejects_invalid_packets_before_write(self):
        self.connect()
        controller = self.app.controller
        for action in (
            lambda: controller.set_step(-1, 0),
            lambda: controller.set_step(0, 16),
            lambda: controller.set_note(8),
            lambda: controller.set_bpm(121),
            lambda: controller.set_tone(2),
            lambda: controller.set_volume(-1),
            lambda: controller.set_volume(201),
            lambda: controller.upload_pattern([0] * 15, 120),
            lambda: controller.upload_pattern([0] * 15 + [16], 120),
        ):
            with self.assertRaises(ValueError):
                action()
        self.assertEqual(self.received(), b"")
        self.assertTrue(controller.connected)


if __name__ == "__main__":
    unittest.main()
