#!/usr/bin/env python3
"""HardBeat control panel. Run with python3 drum_gui.py.

THESIS: A bench instrument, not a dashboard: the pattern is the main control.
OWN-WORLD: Native system typography, cool light surfaces, blue selected steps.
STORY: Connect deliberately, edit a bar, audition voices, and send explicit play.
FIRST VIEWPORT: Connection above a four-row step grid; transport and notes below.
FORM: Operate mode, familiar sequencer controls; no simulated hardware feedback.
"""
import json
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

import serial.tools.list_ports

from drum_control import BPMS, NOTES, DrumController


class DrumApp:
    VOICES = (("Kick", 1, "kick", "K"), ("Snare", 2, "snare", "S"),
              ("Closed hat", 4, "closed", "H"), ("Open hat", 8, "open", "Shift+H"))

    def __init__(self, root):
        self.root = root
        self.controller = DrumController()
        self.pattern = [0] * 16
        self.port = tk.StringVar()
        self.bpm = tk.StringVar(value="120")
        self.tone = tk.BooleanVar(value=False)
        self.volume = tk.IntVar(value=200)
        self.volume_label = tk.StringVar(value="200% · +6 dB")
        self.volume_after = None
        self.last_volume_sent = None
        self.note = 0
        self.held_notes = {}
        self.note_release_timers = {}
        self.status = tk.StringVar(value="Disconnected · edit a pattern, then connect your FPGA")
        self.transport = tk.StringVar(value="Paused command not sent")
        self.connected_controls = []
        self.cells = []
        self.note_buttons = []
        root.title("HardBeat — FPGA control")
        root.geometry("1100x800")
        root.minsize(980, 740)
        root.configure(background="#edf1f5")
        root.protocol("WM_DELETE_WINDOW", self.close)
        style = ttk.Style(root)
        style.configure("TFrame", background="#edf1f5")
        style.configure("TLabel", background="#edf1f5", foreground="#172b40", font=("TkDefaultFont", 12))
        style.configure("Title.TLabel", font=("TkDefaultFont", 24, "bold"))
        style.configure("Section.TLabel", font=("TkDefaultFont", 14, "bold"))
        style.configure("Hint.TLabel", foreground="#4e6072", font=("TkDefaultFont", 11))
        style.configure("TButton", padding=(12, 7))
        outer = ttk.Frame(root, padding=24)
        outer.pack(fill="both", expand=True)
        outer.columnconfigure(0, weight=1)
        ttk.Label(outer, text="HardBeat", style="Title.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(outer, text="Tang Nano 9K · hardware drum machine", style="Hint.TLabel").grid(row=1, column=0, sticky="w", pady=(2, 16))
        self._connection(outer)
        self._pattern(outer)
        self._instruments(outer)
        ttk.Separator(outer).grid(row=5, column=0, sticky="ew", pady=(18, 12))
        ttk.Label(outer, textvariable=self.status, wraplength=1020).grid(row=6, column=0, sticky="w")
        ttk.Label(outer, text="UART sends commands only; the FPGA does not report playback, notes, or receipt. S1/S2 changes are not tracked.",
                  style="Hint.TLabel", wraplength=1020).grid(row=7, column=0, sticky="w", pady=(6, 8))
        self.log = tk.Text(outer, height=4, state="disabled", font=("TkFixedFont", 10),
                           background="#f8fafc", foreground="#34495e", relief="flat", padx=10, pady=8)
        self.log.grid(row=8, column=0, sticky="nsew")
        outer.rowconfigure(8, weight=1)
        self.refresh_ports()
        self.preset("Rock")
        self._connection_state()
        root.bind("<KeyPress>", self.keypress)
        root.bind("<KeyRelease>", self.keyrelease)
        root.bind("<FocusOut>", self.focus_changed)

    def _connection(self, parent):
        frame = ttk.Frame(parent)
        frame.grid(row=2, column=0, sticky="ew", pady=(0, 22))
        ttk.Label(frame, text="Serial port").pack(side="left", padx=(0, 8))
        self.port_box = ttk.Combobox(frame, textvariable=self.port, width=31)
        self.port_box.pack(side="left")
        self.refresh_button = ttk.Button(frame, text="Refresh", command=self.refresh_ports)
        self.refresh_button.pack(side="left", padx=8)
        self.connect_button = ttk.Button(frame, text="Connect", command=self.connect)
        self.connect_button.pack(side="left")
        ttk.Label(frame, text="115200 baud · select the port that triggered your kick", style="Hint.TLabel").pack(side="right")

    def _pattern(self, parent):
        frame = ttk.Frame(parent)
        frame.grid(row=3, column=0, sticky="ew")
        frame.columnconfigure(0, weight=1)
        heading = ttk.Frame(frame)
        heading.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        ttk.Label(heading, text="16-step pattern", style="Section.TLabel").pack(side="left")
        ttk.Button(heading, text="Save…", command=self.save_pattern).pack(side="right", padx=(8, 0))
        ttk.Button(heading, text="Load…", command=self.load_pattern).pack(side="right")
        ttk.Button(heading, text="Clear", command=self.clear_pattern).pack(side="right", padx=8)
        self.preset_name = tk.StringVar(value="Rock")
        presets = ttk.Combobox(heading, textvariable=self.preset_name, state="readonly",
                              values=("Rock", "Four on the floor", "Empty"), width=19)
        presets.pack(side="right", padx=8)
        presets.bind("<<ComboboxSelected>>", lambda event: self.preset(self.preset_name.get()))
        grid = ttk.Frame(frame)
        grid.grid(row=1, column=0, sticky="ew")
        grid.columnconfigure(0, minsize=112)
        for step in range(16):
            grid.columnconfigure(step + 1, weight=1, uniform="steps")
            ttk.Label(grid, text=str(step + 1), anchor="center").grid(row=0, column=step + 1, sticky="ew", pady=(0, 7))
        for row, (label, bit, _, _) in enumerate(self.VOICES):
            ttk.Label(grid, text=label).grid(row=row + 1, column=0, sticky="w")
            buttons = []
            for step in range(16):
                button = tk.Button(grid, text="·", width=3, height=2, relief="flat", borderwidth=1,
                                   font=("TkDefaultFont", 13, "bold"), takefocus=True,
                                   command=lambda s=step, b=bit: self.toggle_step(s, b))
                button.grid(row=row + 1, column=step + 1, sticky="nsew",
                            padx=(7 if step % 4 == 0 else 2, 2), pady=3)
                buttons.append(button)
            self.cells.append(buttons)
        ttk.Label(frame, text="Each group of four steps is one beat. Open and closed hats are mutually exclusive per step.",
                  style="Hint.TLabel").grid(row=2, column=0, sticky="w", pady=(9, 14))
        transport = ttk.Frame(frame)
        transport.grid(row=3, column=0, sticky="ew")
        for label, fn in (("Play", self.play), ("Pause", self.pause), ("Send pattern", self.upload)):
            button = ttk.Button(transport, text=label, command=fn)
            button.pack(side="left", padx=(0, 8))
            self.connected_controls.append(button)
        ttk.Label(transport, text="Tempo").pack(side="left", padx=(16, 6))
        tempo = ttk.Combobox(transport, textvariable=self.bpm, values=BPMS, state="readonly", width=5)
        tempo.pack(side="left")
        tempo.bind("<<ComboboxSelected>>", lambda event: self.change_bpm())
        ttk.Label(transport, text="BPM").pack(side="left", padx=6)
        ttk.Label(transport, textvariable=self.transport, style="Hint.TLabel").pack(side="right")

    def _instruments(self, parent):
        frame = ttk.Frame(parent)
        frame.grid(row=4, column=0, sticky="ew", pady=(22, 0))
        frame.columnconfigure(0, weight=1)
        ttk.Label(frame, text="Audition drums", style="Section.TLabel").grid(row=0, column=0, sticky="w")
        pads = ttk.Frame(frame)
        pads.grid(row=1, column=0, sticky="w", pady=(8, 16))
        for label, _, voice, shortcut in self.VOICES:
            button = ttk.Button(pads, text=f"{label}  [{shortcut}]", command=lambda v=voice: self.trigger(v))
            button.pack(side="left", padx=(0, 8))
            self.connected_controls.append(button)
        notes = ttk.Frame(frame)
        notes.grid(row=2, column=0, sticky="ew")
        ttk.Label(notes, text="Synth notes", style="Section.TLabel").pack(side="left", padx=(0, 16))
        tone = ttk.Checkbutton(notes, text="Latch tone", variable=self.tone, command=self.change_tone)
        tone.pack(side="left")
        self.connected_controls.append(tone)
        ttk.Label(notes, text="Hold a note or key 1–8 · release to fade out", style="Hint.TLabel").pack(side="right")
        keyboard = ttk.Frame(frame)
        keyboard.grid(row=3, column=0, sticky="ew", pady=(8, 0))
        for index, name in enumerate(NOTES):
            keyboard.columnconfigure(index, weight=1, uniform="notes")
            button = tk.Button(keyboard, text=f"{name}\n{index + 1}", height=2, relief="flat", takefocus=True,
                               font=("TkDefaultFont", 12), command=lambda n=index: self.tap_note(n))
            button.grid(row=0, column=index, sticky="ew", padx=(0, 5))
            button.bind("<ButtonPress-1>", lambda event, n=index: self.mouse_note_press(event, n))
            button.bind("<ButtonRelease-1>", lambda event: self.mouse_note_release(event))
            self.note_buttons.append(button)
            self.connected_controls.append(button)
        amplitude = ttk.Frame(frame)
        amplitude.grid(row=4, column=0, sticky="ew", pady=(16, 0))
        amplitude.columnconfigure(1, weight=1)
        ttk.Label(amplitude, text="Master amplitude", style="Section.TLabel").grid(row=0, column=0, sticky="w", padx=(0, 16))
        self.volume_scale = tk.Scale(amplitude, from_=0, to=200, orient="horizontal", resolution=1, length=380,
                                     variable=self.volume, showvalue=False, command=self.change_volume,
                                     background="#edf1f5", highlightthickness=0, relief="flat",
                                     troughcolor="#dae7f2", takefocus=True)
        self.volume_scale.grid(row=0, column=1, sticky="ew")
        ttk.Label(amplitude, textvariable=self.volume_label, width=17, anchor="e").grid(row=0, column=2, padx=(12, 0))
        ttk.Label(frame, text="0% mutes all audio · 100% original level · 200% boosted level. Loud voice combinations may clip.",
                  style="Hint.TLabel").grid(row=5, column=0, sticky="w", pady=(4, 0))

    def change_volume(self, value):
        percent = max(0, min(200, int(round(float(value)))))
        if self.volume.get() != percent:
            self.volume.set(percent)
        suffix = " · mute" if percent == 0 else " · original" if percent == 100 else " · +6 dB" if percent == 200 else ""
        self.volume_label.set(f"{percent}%{suffix}")
        if self.volume_after is not None:
            self.root.after_cancel(self.volume_after)
            self.volume_after = None
        if not self.controller.connected:
            self.status.set(f"Master amplitude {percent}% selected locally · connect to send it to the FPGA")
            return
        # Coalesce dragging events rather than sending every mouse movement.
        self.volume_after = self.root.after(80, self.send_volume)

    def send_volume(self):
        self.volume_after = None
        percent = self.volume.get()
        if percent != self.last_volume_sent:
            if self._send(lambda: self.controller.set_volume(percent), f"Master amplitude {percent}%"):
                self.last_volume_sent = percent

    def _record(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", text + "\n")
        if int(self.log.index("end-1c").split(".")[0]) > 100:
            self.log.delete("1.0", "2.0")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _connection_state(self):
        connected = self.controller.connected
        for control in self.connected_controls:
            control.configure(state="normal" if connected else "disabled")
        self.connect_button.configure(text="Disconnect" if connected else "Connect")
        self.port_box.configure(state="disabled" if connected else "normal")
        self.refresh_button.configure(state="disabled" if connected else "normal")
        for index, button in enumerate(self.note_buttons):
            button.configure(background="#c4def4" if index == self.note else "#ffffff",
                             foreground="#172b40", activebackground="#a8cfee")

    def _send(self, action, text):
        if not self.controller.connected:
            self.status.set("Not sent · select the FPGA UART port and click Connect first")
            self._record(self.status.get())
            return False
        try:
            action()
        except (OSError, ValueError) as exc:
            self.controller.disconnect()
            self.cancel_note_inputs()
            self.tone.set(False)
            self.transport.set("Disconnected")
            self.status.set(f"Serial error: {exc}. Check the cable and reconnect.")
            self._record(self.status.get())
            self._connection_state()
            return False
        self.status.set(text + " · sent, not acknowledged")
        self._record(text)
        return True

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports() if "usb" in p.device.lower()]
        self.port_box.configure(values=ports)
        if self.port.get() not in ports and ports:
            self.port.set(next((p for p in ports if p.endswith("101")), ports[0]))
        if not ports:
            self.status.set("No USB serial ports found. Connect the board, then Refresh; a port can also be entered manually.")

    def connect(self):
        if self.controller.connected:
            self.cancel_note_inputs()
            self.controller.disconnect()
            self.tone.set(False)
            self.last_volume_sent = None
            self.transport.set("Disconnected")
            self.status.set("Disconnected · pause and tone-off requested before closing")
            self._connection_state()
            return
        if not self.port.get().strip():
            self.status.set("Select or enter a serial port first.")
            return
        try:
            self.controller.connect(self.port.get().strip())
            self.controller.upload_pattern(self.pattern, int(self.bpm.get()))
            self.controller.set_volume(self.volume.get())
            self.last_volume_sent = self.volume.get()
        except (OSError, ValueError) as exc:
            self.controller.disconnect()
            self.status.set(f"Cannot connect: {exc}. Close other serial programs and check the port.")
            self._connection_state()
            return
        self.note = 0
        self.cancel_note_inputs()
        self.tone.set(False)
        self.transport.set("Pause sent")
        self.status.set(f"Connected to {self.controller.port} · pattern and {self.volume.get()}% amplitude sent; pause and tone-off sent")
        self._record(self.status.get())
        self._connection_state()

    def _render_pattern(self):
        for row, (_, bit, _, _) in enumerate(self.VOICES):
            for step, button in enumerate(self.cells[row]):
                on = bool(self.pattern[step] & bit)
                button.configure(text="●" if on else "·", background="#176baf" if on else "#ffffff",
                                 foreground="#ffffff" if on else "#627589",
                                 activebackground="#105b98" if on else "#dae7f2",
                                 activeforeground="#ffffff" if on else "#172b40")

    def toggle_step(self, step, bit):
        mask = self.pattern[step] ^ bit
        if mask & bit and bit in (4, 8):
            mask &= ~(8 if bit == 4 else 4)
        self.pattern[step] = mask
        self._render_pattern()
        if self.controller.connected:
            self._send(lambda: self.controller.set_step(step, mask), f"Step {step + 1} mask {mask:04b}")
        else:
            self.status.set("Pattern edited locally · connect to send it to the FPGA")

    def preset(self, name):
        if name == "Rock":
            self.pattern = [4 | (1 if s % 4 == 0 else 0) | (2 if s % 8 == 4 else 0) for s in range(16)]
        elif name == "Four on the floor":
            self.pattern = [(1 if s % 4 == 0 else 0) | (4 if s % 2 == 0 else 0) | (2 if s % 8 == 4 else 0) for s in range(16)]
        else:
            self.pattern = [0] * 16
        self._render_pattern()
        if self.controller.connected:
            self.upload()

    def clear_pattern(self):
        self.pattern = [0] * 16
        self._render_pattern()
        if self.controller.connected:
            self._send(self.controller.clear, "Pattern cleared")
        else:
            self.status.set("Local pattern cleared")

    def upload(self):
        self._send(lambda: self.controller.upload_pattern(self.pattern, int(self.bpm.get())), "16-step pattern and tempo sent")

    def change_bpm(self):
        self._send(lambda: self.controller.set_bpm(int(self.bpm.get())), f"Tempo {self.bpm.get()} BPM")

    def play(self):
        if self._send(self.controller.play, "Play"):
            self.transport.set("Play sent")

    def pause(self):
        if self._send(self.controller.pause, "Pause"):
            self.transport.set("Pause sent")

    def trigger(self, voice):
        self._send(lambda: self.controller.trigger(voice), f"Audition {voice}")

    def press_note(self, index, source):
        timer = self.note_release_timers.pop(source, None)
        if timer is not None:
            self.root.after_cancel(timer)
        if self.held_notes.get(source) == index:
            return
        def send_note():
            self.controller.set_note(index)
            self.controller.set_tone(True)
        if self._send(send_note, f"Note {NOTES[index]} · attack / sustain"):
            self.held_notes.pop(source, None)
            self.held_notes[source] = index
            self.note = index
            self._connection_state()

    def release_note(self, source):
        timer = self.note_release_timers.pop(source, None)
        if timer is not None:
            self.root.after_cancel(timer)
        if source not in self.held_notes:
            return
        self.held_notes.pop(source)
        if self.held_notes:
            index = next(reversed(self.held_notes.values()))
            if self._send(lambda: self.controller.set_note(index), f"Held note {NOTES[index]}"):
                self.note = index
                self._connection_state()
        elif not self.tone.get():
            self._send(lambda: self.controller.set_tone(False), "Note released · fading out")

    def tap_note(self, index):
        # Keyboard activation of a focused button produces a short audition.
        self.press_note(index, "tap")
        if "tap" in self.held_notes:
            self.note_release_timers["tap"] = self.root.after(160, lambda: self.release_note("tap"))

    def mouse_note_press(self, event, index):
        if self.controller.connected:
            event.widget.focus_set()
            self.press_note(index, "mouse")
        return "break"

    def mouse_note_release(self, event):
        self.release_note("mouse")
        return "break"

    def cancel_note_inputs(self):
        for timer in self.note_release_timers.values():
            self.root.after_cancel(timer)
        self.note_release_timers.clear()
        self.held_notes.clear()

    def focus_changed(self, event):
        # Child-to-child focus changes are harmless; leaving the app releases
        # held notes so a missed mouse/key release cannot leave a stuck tone.
        self.root.after_idle(self.release_unfocused_notes)

    def release_unfocused_notes(self):
        if self.root.focus_get() is None and self.held_notes:
            self.cancel_note_inputs()
            if self.controller.connected and not self.tone.get():
                self._send(lambda: self.controller.set_tone(False), "Focus lost · note released")

    def change_tone(self):
        gate = self.tone.get() or bool(self.held_notes)
        self._send(lambda: self.controller.set_tone(gate), "Tone latched" if self.tone.get() else "Tone latch off")

    def keypress(self, event):
        if isinstance(event.widget, (ttk.Entry, ttk.Combobox, tk.Entry, tk.Text)):
            return
        if event.char in "12345678" and event.char:
            self.press_note(int(event.char) - 1, f"key:{event.keysym}")
            return "break"
        elif event.char in {"k", "s", "h", "H"}:
            self.trigger({"k": "kick", "s": "snare", "h": "closed", "H": "open"}[event.char])

    def keyrelease(self, event):
        source = f"key:{event.keysym}"
        if source in self.held_notes:
            timer = self.note_release_timers.pop(source, None)
            if timer is not None:
                self.root.after_cancel(timer)
            # Auto-repeat release/press pairs cancel this pending release.
            self.note_release_timers[source] = self.root.after(30, lambda: self.release_note(source))
            return "break"

    def save_pattern(self):
        path = filedialog.asksaveasfilename(parent=self.root, title="Save pattern", defaultextension=".json",
                                          filetypes=(("Drum patterns", "*.json"),))
        if path:
            try:
                Path(path).write_text(json.dumps({"bpm": int(self.bpm.get()), "steps": self.pattern}, indent=2) + "\n")
                self.status.set(f"Saved {Path(path).name}")
            except OSError as exc:
                messagebox.showerror("Cannot save pattern", str(exc), parent=self.root)

    def load_pattern(self):
        path = filedialog.askopenfilename(parent=self.root, title="Load pattern", filetypes=(("Drum patterns", "*.json"),))
        if not path:
            return
        try:
            data = json.loads(Path(path).read_text())
            steps, bpm = data["steps"], data["bpm"]
            if (not isinstance(steps, list) or len(steps) != 16 or
                    any(type(mask) is not int or not 0 <= mask <= 15 or mask & 12 == 12 for mask in steps) or
                    type(bpm) is not int or bpm not in BPMS):
                raise ValueError("Use 16 integer masks (0–15), no simultaneous open/closed hats, and a supported BPM.")
        except (OSError, ValueError, TypeError, KeyError) as exc:
            messagebox.showerror("Cannot load pattern", str(exc), parent=self.root)
            return
        self.pattern = steps
        self.bpm.set(str(bpm))
        self._render_pattern()
        if self.controller.connected:
            self.upload()
        else:
            self.status.set(f"Loaded {Path(path).name} locally · connect to send")

    def close(self):
        self.cancel_note_inputs()
        if self.volume_after is not None:
            self.root.after_cancel(self.volume_after)
        self.controller.disconnect()
        self.root.destroy()


def main():
    root = tk.Tk()
    DrumApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
