"""Tests for the data model used by the Tk Lychee monitor example."""

import sys
import unittest
from pathlib import Path

from axon import SampleBlock

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
