"""Tests for the data model used by the Tk Lychee monitor example."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from axon import AxonError, SampleBlock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lychee_monitor import LycheeMonitor, WaveformBuffer, can_add_simulator, parse_args


class _FakeWidget:
    def __init__(self):
        self.configured = {}

    def configure(self, **kwargs):
        self.configured.update(kwargs)


class _FakeSession:
    def __init__(self):
        self.disposed = False
        self.filters = []
        self.fail_configuration = False

    def add_filter(self, stage):
        if self.fail_configuration:
            raise AxonError(1, "filter setup failed")
        self.filters.append(stage)

    def dispose(self):
        self.disposed = True


class _FakeVariable:
    def __init__(self):
        self.value = None

    def set(self, value):
        self.value = value


class TestWaveformBuffer(unittest.TestCase):
    def test_retains_only_the_latest_window_for_each_channel(self):
        """A monitor redraw must not retain samples older than its visible window."""
        buffer = WaveformBuffer(window_seconds=1.0)
        buffer.append(SampleBlock(
            start_timestamp=0,
            sample_rate_hz=4.0,
            num_channels=2,
            num_samples=4,
            # SampleBlock.data is interleaved: [s0c0, s0c1, s1c0, s1c1, ...].
            data=[1, 10, 2, 20, 3, 30, 4, 40],
        ))
        buffer.append(SampleBlock(
            start_timestamp=1_000_000,
            sample_rate_hz=4.0,
            num_channels=2,
            num_samples=4,
            data=[5, 50, 6, 60, 7, 70, 8, 80],
        ))

        self.assertEqual(buffer.channel_samples(0), [5, 6, 7, 8])
        self.assertEqual(buffer.channel_samples(1), [50, 60, 70, 80])
        self.assertEqual(buffer.sample_rate_hz, 4.0)

    def test_irregular_blocks_are_not_plotted_on_a_uniform_time_grid(self):
        buffer = WaveformBuffer(window_seconds=1.0)
        buffer.append(SampleBlock(
            start_timestamp=0,
            sample_rate_hz=4.0,
            num_channels=1,
            num_samples=2,
            data=[1, 2],
        ))
        buffer.append(SampleBlock(
            start_timestamp=1_000_000,
            sample_rate_hz=4.0,
            num_channels=1,
            num_samples=2,
            data=[1, 2],
            sample_offsets_us=[0, 500_000],
        ))

        self.assertEqual(buffer.channel_count, 0)


class TestMonitorConfiguration(unittest.TestCase):
    def test_monitor_starts_without_device_command_line_arguments(self):
        args = parse_args([])

        self.assertFalse(hasattr(args, "sim"))
        self.assertFalse(hasattr(args, "serial"))

    def test_simulator_can_be_added_only_before_collection(self):
        self.assertTrue(can_add_simulator(axon_started=True, simulator_added=False, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=False, simulator_added=False, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=True, simulator_added=True, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=True, simulator_added=False, collecting=True))

    def test_device_callback_matches_binding_signature(self):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.device_events = __import__("queue").Queue()

        monitor._on_device_event("SIM-1", "Lychee", "PFC", True)

        self.assertEqual(monitor.device_events.get_nowait(), ("SIM-1", "Lychee", True))

    def _configured_monitor(self, stream, session):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.root = None
        monitor.args = SimpleNamespace(no_filter=False, notch=False)
        def new_session(serial, stream_id=None):
            monitor.created_session_args = (serial, stream_id)
            return session
        monitor.axon = SimpleNamespace(device_streams=lambda serial: [stream], new_session=new_session)
        monitor.session = None
        monitor.buffer = WaveformBuffer()
        monitor.device_picker = _FakeWidget()
        monitor.start_button = _FakeWidget()
        monitor.stop_button = _FakeWidget()
        monitor.simulator_button = _FakeWidget()
        monitor._simulator_id = None
        monitor.status = _FakeVariable()
        monitor._selected_serial = lambda: "SIM-1"
        monitor.created_session = session
        monitor.created_session_args = None
        return monitor

    def test_start_session_uses_uniform_eeg_stream_and_current_filter_config(self):
        stream = SimpleNamespace(
            id="eeg", kind=0, sampling_mode=0, sample_rate_hz=256.0,
            num_channels=8,
        )
        session = _FakeSession()
        monitor = self._configured_monitor(stream, session)
        monitor.start_session()

        self.assertEqual(monitor.created_session_args, ("SIM-1", "eeg"))
        self.assertEqual(len(session.filters), 1)
        self.assertFalse(hasattr(session.filters[0], "sample_rate_hz"))
        self.assertIn("8 通道", monitor.status.value)
        self.assertIn("256 Hz", monitor.status.value)

    def test_start_session_rejects_irregular_eeg_before_opening_session(self):
        stream = SimpleNamespace(
            id="eeg", kind=0, sampling_mode=1, sample_rate_hz=256.0,
            num_channels=8,
        )
        session = _FakeSession()
        monitor = self._configured_monitor(stream, session)
        errors = []

        with patch("lychee_monitor.messagebox.showerror", side_effect=lambda *args, **kwargs: errors.append(args)):
            monitor.start_session()

        self.assertIsNone(monitor.session)
        self.assertEqual(monitor.created_session_args, None)
        self.assertTrue(errors)

    def test_start_session_disposes_session_when_filter_configuration_fails(self):
        stream = SimpleNamespace(
            id="eeg", kind=0, sampling_mode=0, sample_rate_hz=256.0,
            num_channels=8,
        )
        session = _FakeSession()
        session.fail_configuration = True
        monitor = self._configured_monitor(stream, session)
        with patch("lychee_monitor.messagebox.showerror"):
            monitor.start_session()

        self.assertTrue(session.disposed)
        self.assertIsNone(monitor.session)

    def test_stop_session_releases_session_and_restores_start_controls(self):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.session = _FakeSession()
        monitor.buffer = WaveformBuffer()
        monitor.device_picker = _FakeWidget()
        monitor.start_button = _FakeWidget()
        monitor.stop_button = _FakeWidget()
        monitor.simulator_button = _FakeWidget()
        monitor._simulator_id = None
        monitor.status = _FakeVariable()

        monitor.stop_session()

        self.assertIsNone(monitor.session)
        self.assertTrue(monitor.buffer.channel_count == 0)
        self.assertTrue(monitor.start_button.configured["state"] == "normal")
        self.assertTrue(monitor.stop_button.configured["state"] == "disabled")
        self.assertTrue(monitor.device_picker.configured["state"] == "readonly")


if __name__ == "__main__":
    unittest.main()
