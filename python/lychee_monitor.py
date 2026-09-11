#!/usr/bin/env python3
"""Lychee EEG desktop monitor with device selection and scrolling waveforms."""

import argparse
import ctypes
import math
import sys
import tkinter as tk
from collections import deque
from queue import Empty, Queue
from tkinter import messagebox, ttk

from axon import Axon, AxonError, AxonFilterStageConfig, SampleBlock
from axon._types import (
    AXON_LOG_DEBUG,
    AXON_LOG_ERROR,
    AXON_LOG_INFO,
    AXON_LOG_OFF,
    AXON_LOG_TRACE,
    AXON_LOG_WARN,
    AxonLogConfig,
)

SIM_SERIAL = "lychee-sim"
LOG_LEVELS = {
    "off": AXON_LOG_OFF,
    "error": AXON_LOG_ERROR,
    "warn": AXON_LOG_WARN,
    "info": AXON_LOG_INFO,
    "debug": AXON_LOG_DEBUG,
    "trace": AXON_LOG_TRACE,
}


def init_log(lib, level_name):
    level = LOG_LEVELS[level_name]
    if level == AXON_LOG_OFF:
        return
    config = AxonLogConfig()
    config.level = level
    config.log_path = None
    lib.axon_log_init(ctypes.byref(config))


class WaveformBuffer:
    """Keeps a fixed-duration, channel-major window of EEG samples."""

    def __init__(self, window_seconds=5.0):
        self.window_seconds = window_seconds
        self.sample_rate_hz = 0.0
        self._channels = []

    def clear(self):
        self.sample_rate_hz = 0.0
        self._channels = []

    def append(self, block: SampleBlock):
        if block.num_channels <= 0 or block.num_samples <= 0:
            return
        if len(self._channels) != block.num_channels or self.sample_rate_hz != block.sample_rate_hz:
            self.sample_rate_hz = block.sample_rate_hz
            self._channels = [deque() for _ in range(block.num_channels)]

        capacity = max(1, math.ceil(self.window_seconds * self.sample_rate_hz))
        for channel, samples in enumerate(self._channels):
            offset = channel * block.num_samples
            samples.extend(block.data[offset:offset + block.num_samples])
            while len(samples) > capacity:
                samples.popleft()

    @property
    def channel_count(self):
        return len(self._channels)

    def channel_samples(self, channel):
        return list(self._channels[channel])


class LycheeMonitor:
    POLL_MS = 50
    DRAW_MS = 50

    def __init__(self, root, args):
        self.root = root
        self.args = args
        self.axon = Axon()
        self.session = None
        self.device_events = Queue()
        self.devices = {}
        self.buffer = WaveformBuffer(args.window)
        self.selected_device = tk.StringVar()
        self.status = tk.StringVar(value="正在启动 Lychee 监听…")

        self._build_ui()
        init_log(self.axon._lib, args.log_level)
        self.axon.set_device_callback(self._on_device_event)
        self._start_listener()
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.root.after(self.POLL_MS, self._poll)
        self.root.after(self.DRAW_MS, self._draw)

    def _build_ui(self):
        self.root.title("Axon · Lychee EEG Monitor")
        self.root.configure(bg="#10151b")
        self.root.minsize(920, 600)

        controls = ttk.Frame(self.root, padding=(14, 12, 14, 8))
        controls.pack(fill=tk.X)
        ttk.Label(controls, text="传感器：").pack(side=tk.LEFT)
        self.device_picker = ttk.Combobox(
            controls, textvariable=self.selected_device, state="readonly", width=42
        )
        self.device_picker.pack(side=tk.LEFT, padx=(0, 8))
        self.start_button = ttk.Button(controls, text="开始采集", command=self.start_session)
        self.start_button.pack(side=tk.LEFT)
        ttk.Label(controls, textvariable=self.status).pack(side=tk.RIGHT)

        self.canvas = tk.Canvas(
            self.root, bg="#07120d", highlightthickness=0, cursor="crosshair"
        )
        self.canvas.pack(fill=tk.BOTH, expand=True, padx=14, pady=(0, 8))
        ttk.Label(
            self.root,
            text="显示最近 %.1f 秒  ·  竖线 0.5 秒  ·  自动量程" % self.args.window,
            padding=(14, 0, 14, 12),
        ).pack(anchor=tk.W)

    def _start_listener(self):
        try:
            if self.args.sim:
                self.axon.add_simulator(SIM_SERIAL, channels=3, sample_rate_hz=250.0)
                self.axon.start()
                self.status.set("模拟器已就绪，选择 lychee-sim 开始采集")
            else:
                self.axon.start()
                if self.args.serial:
                    self._add_device(self.args.serial, "指定的传感器")
                    self.status.set("已指定传感器，选择后开始采集")
                else:
                    self.status.set("正在监听 TCP:31200 / UDP:31300 / 组播 239.0.0.6:31400")
        except AxonError as error:
            self.status.set(f"监听启动失败：{error}")
            messagebox.showerror("Lychee 监听失败", str(error), parent=self.root)

    def _on_device_event(self, serial, name, _model, _channels, _sample_rate, connected):
        # Called from a Rust worker thread: transfer work to the Tk thread only.
        self.device_events.put((serial, name, connected))

    def _poll(self):
        try:
            while True:
                serial, name, connected = self.device_events.get_nowait()
                if connected:
                    self._add_device(serial, name)
                else:
                    self._remove_device(serial)
        except Empty:
            pass

        if self.session:
            try:
                for _ in range(64):
                    self.buffer.append(self.session.data_queue.get_nowait())
            except Empty:
                pass
        self.root.after(self.POLL_MS, self._poll)

    def _add_device(self, serial, name):
        if not serial:
            return
        label = f"{serial}  ·  {name or 'Lychee'}"
        self.devices[serial] = label
        self.device_picker["values"] = tuple(self.devices.values())
        if not self.selected_device.get():
            self.selected_device.set(label)
        if not self.session:
            self.status.set(f"发现传感器 {serial}，请选择后开始采集")

    def _remove_device(self, serial):
        label = self.devices.pop(serial, None)
        self.device_picker["values"] = tuple(self.devices.values())
        if label and self.selected_device.get() == label and not self.session:
            self.selected_device.set("")
            self.status.set(f"传感器 {serial} 已离线")

    def _selected_serial(self):
        label = self.selected_device.get()
        return next((serial for serial, value in self.devices.items() if value == label), None)

    def start_session(self):
        serial = self._selected_serial()
        if not serial:
            messagebox.showinfo("请选择传感器", "请先从列表中选择一个已发现的 Lychee 传感器。", parent=self.root)
            return
        try:
            info = self.axon.device_info(serial)
            session = self.axon.new_session(serial)
            if not self.args.no_filter:
                # Same default as the native debugger: one IIR band-pass section
                # at 0.4–70 Hz. Q must be passed explicitly (the FFI rejects 0)
                # and is derived exactly like the native side: q = f0 / bandwidth.
                bp_low, bp_high = 0.4, 70.0
                bp_q = math.sqrt(bp_low * bp_high) / (bp_high - bp_low)
                session.add_filter(AxonFilterStageConfig(
                    filter_type=1, kind=2, cutoff_hz=bp_low, cutoff2_hz=bp_high,
                    sample_rate_hz=info.sample_rate_hz, order=1, q=bp_q,
                ))
            if self.args.notch:
                session.add_filter(AxonFilterStageConfig(
                    filter_type=1, kind=4, cutoff_hz=50.0,
                    sample_rate_hz=info.sample_rate_hz, order=4, q=30.0,
                ))
        except AxonError as error:
            messagebox.showerror("无法开始采集", str(error), parent=self.root)
            return

        self.session = session
        self.buffer.clear()
        self.device_picker.configure(state="disabled")
        self.start_button.configure(state="disabled")
        self.status.set(f"正在采集 {serial} · {info.num_channels} 通道 · {info.sample_rate_hz:.0f} Hz")

    def _draw(self):
        canvas = self.canvas
        width, height = max(1, canvas.winfo_width()), max(1, canvas.winfo_height())
        canvas.delete("all")
        channels = self.buffer.channel_count
        if not channels:
            canvas.create_text(
                width / 2, height / 2,
                text="等待传感器数据…", fill="#80a897", font=("Segoe UI", 16),
            )
            self.root.after(self.DRAW_MS, self._draw)
            return

        lane_height = height / channels
        for x in range(0, width + 1, max(1, width // int(self.args.window * 2))):
            canvas.create_line(x, 0, x, height, fill="#17432e")
        for channel in range(channels):
            top, bottom = channel * lane_height, (channel + 1) * lane_height
            center = (top + bottom) / 2
            canvas.create_line(0, center, width, center, fill="#2b6245")
            canvas.create_line(0, bottom, width, bottom, fill="#17432e")
            canvas.create_text(8, top + 12, text=f"CH {channel + 1}", anchor=tk.W, fill="#93cdb1")
            samples = self.buffer.channel_samples(channel)
            if len(samples) > 1:
                amplitude = max(50.0, max(abs(value) for value in samples))
                scale = (lane_height * 0.36) / amplitude
                start_x = width * (1 - len(samples) / max(1, self.args.window * self.buffer.sample_rate_hz))
                points = []
                for index, value in enumerate(samples):
                    x = start_x + index * width / max(1, self.args.window * self.buffer.sample_rate_hz)
                    points.extend((x, center - value * scale))
                canvas.create_line(*points, fill="#42ef9c", width=1.4)
                canvas.create_text(
                    width - 8, top + 12, text=f"±{amplitude:.0f} µV",
                    anchor=tk.E, fill="#6da886",
                )
        self.root.after(self.DRAW_MS, self._draw)

    def close(self):
        try:
            if self.session:
                self.session.dispose()
            self.axon.dispose()
        finally:
            self.root.destroy()


def main():
    parser = argparse.ArgumentParser(description="Lychee EEG 实时波形监测器")
    parser.add_argument("--sim", action="store_true", help="使用内置模拟器")
    parser.add_argument("--serial", metavar="HEX", help="直接添加已知设备 serial")
    parser.add_argument("--window", type=float, default=10.0, help="波形显示时窗（秒）")
    parser.add_argument("--no-filter", action="store_true", help="禁用 0.4–70 Hz 带通滤波")
    parser.add_argument("--notch", action="store_true", help="叠加 50 Hz 陷波（Q=30，接硬件时使用）")
    parser.add_argument("--log-level", choices=LOG_LEVELS, default="off", help="Rust 日志级别")
    args = parser.parse_args()
    if args.sim and args.serial:
        parser.error("--sim 和 --serial 不能同时使用")
    if args.window <= 0:
        parser.error("--window 必须大于 0")

    root = tk.Tk()
    LycheeMonitor(root, args)
    root.mainloop()


if __name__ == "__main__":
    main()
