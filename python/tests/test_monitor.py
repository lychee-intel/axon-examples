"""Tests for the data model used by the Tk Lychee monitor example."""

import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, Mock

from axon import Axon, AxonError, DeliveryKinds, DeviceModel, SampleBlock

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
        self.pipeline = None
        self.subscription = None

    def create_pipeline(self, stream_id):
        self.stream_id = stream_id
        self.pipeline = _FakeSession()
        self.pipeline.fail_configuration = self.fail_configuration
        return self.pipeline

    def subscribe(self, **options):
        self.subscription_options = options
        self.subscription = _FakeSession()
        return self.subscription

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
    @unittest.skipUnless(os.environ.get("AXON_RUN_NATIVE_TESTS") == "1",
                         "set AXON_RUN_NATIVE_TESTS=1 with a matching native library")
    def test_native_simulator_delivers_processed_samples_and_can_restart(self):
        with Axon() as axon:
            axon.start()
            simulator = axon.start_simulator(DeviceModel.LYCHEE_BCI100, "0A1B2C")
            try:
                stream = next(s for s in axon.device_streams(simulator.serial) if s.id == "eeg")
                monitor = self._configured_monitor(stream, None)
                monitor.axon = axon
                monitor._selected_serial = lambda: simulator.serial
                # Reopening the same device exercises child cleanup as well as delivery.
                for _ in range(2):
                    try:
                        with patch("lychee_monitor.messagebox.showerror") as show_error:
                            monitor.start_session()
                        show_error.assert_not_called()
                        self.assertIsNotNone(monitor.subscription)
                        block = monitor.subscription.data_queue.get(timeout=5)
                        self.assertEqual(block.num_channels, stream.num_channels)
                        self.assertEqual(block.sample_rate_hz, stream.sample_rate_hz)
                        self.assertGreater(block.num_samples, 0)
                        self.assertEqual(len(block.data), block.num_channels * block.num_samples)
                        monitor.buffer.append(block)
                        self.assertEqual(monitor.buffer.channel_count, stream.num_channels)
                    finally:
                        monitor.stop_session()
            finally:
                simulator.stop()

    def test_monitor_starts_without_device_command_line_arguments(self):
        args = parse_args([])

        self.assertFalse(hasattr(args, "sim"))
        self.assertFalse(hasattr(args, "serial"))

    def test_simulator_can_be_added_only_before_collection(self):
        self.assertTrue(can_add_simulator(axon_started=True, simulator_added=False, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=False, simulator_added=False, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=True, simulator_added=True, collecting=False))
        self.assertFalse(can_add_simulator(axon_started=True, simulator_added=False, collecting=True))

    def test_add_simulator_uses_current_device_model(self):
        monitor = self._configured_monitor(None, None)
        monitor._axon_started = True
        start_simulator = Mock(return_value=SimpleNamespace(serial="0A1B2C"))
        monitor.axon = SimpleNamespace(start_simulator=start_simulator)

        monitor.add_simulator()

        start_simulator.assert_called_once_with(DeviceModel.LYCHEE_BCI100, "0A1B2C")
        self.assertIsNotNone(monitor._simulator)

    def test_device_callback_matches_binding_signature(self):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.device_events = __import__("queue").Queue()

        monitor._on_device_event("SIM-1", "Lychee", "BCI100", True)

        self.assertEqual(monitor.device_events.get_nowait(), ("SIM-1", "Lychee", True))

    def _configured_monitor(self, stream, session):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.root = None
        monitor.args = SimpleNamespace(no_filter=False, notch=False)
        def new_session(serial):
            monitor.created_session_args = (serial,)
            return session
        monitor.axon = SimpleNamespace(device_streams=lambda serial: [stream], new_session=new_session)
        monitor.session = None
        monitor.pipeline = None
        monitor.subscription = None
        monitor.buffer = WaveformBuffer()
        monitor.device_picker = _FakeWidget()
        monitor.start_button = _FakeWidget()
        monitor.stop_button = _FakeWidget()
        monitor.simulator_button = _FakeWidget()
        monitor._simulator = None
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
        with patch("lychee_monitor.messagebox.showerror"):
            monitor.start_session()

        self.assertEqual(monitor.created_session_args, ("SIM-1",))
        self.assertEqual(session.stream_id, "eeg")
        self.assertIs(monitor.session, session)
        self.assertIs(monitor.pipeline, session.pipeline)
        self.assertIs(monitor.subscription, session.pipeline.subscription)
        self.assertEqual(session.pipeline.subscription_options,
                         {"delivery_mask": DeliveryKinds.DATA})
        self.assertEqual(len(session.pipeline.filters), 1)
        self.assertFalse(hasattr(session.pipeline.filters[0], "sample_rate_hz"))
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
        self.assertTrue(session.pipeline.disposed)
        self.assertIsNone(monitor.session)

    def test_stop_session_releases_session_and_restores_start_controls(self):
        monitor = LycheeMonitor.__new__(LycheeMonitor)
        monitor.session = _FakeSession()
        monitor.pipeline = _FakeSession()
        monitor.subscription = _FakeSession()
        owned = (monitor.session, monitor.pipeline, monitor.subscription)
        monitor.buffer = WaveformBuffer()
        monitor.device_picker = _FakeWidget()
        monitor.start_button = _FakeWidget()
        monitor.stop_button = _FakeWidget()
        monitor.simulator_button = _FakeWidget()
        monitor._simulator = None
        monitor.status = _FakeVariable()

        monitor.stop_session()

        self.assertIsNone(monitor.session)
        self.assertIsNone(monitor.pipeline)
        self.assertIsNone(monitor.subscription)
        self.assertTrue(all(item.disposed for item in owned))
        self.assertTrue(monitor.buffer.channel_count == 0)
        self.assertTrue(monitor.start_button.configured["state"] == "normal")
        self.assertTrue(monitor.stop_button.configured["state"] == "disabled")
        self.assertTrue(monitor.device_picker.configured["state"] == "readonly")

    def test_stop_still_releases_parents_when_subscription_cleanup_fails(self):
        stream = SimpleNamespace(id="eeg", kind=0, sampling_mode=0,
                                 sample_rate_hz=250, num_channels=3)
        session = _FakeSession()
        monitor = self._configured_monitor(stream, session)
        monitor.start_session()
        pipeline = monitor.pipeline
        monitor.subscription.dispose = Mock(side_effect=RuntimeError("close failed"))
        with self.assertRaisesRegex(RuntimeError, "close failed"):
            monitor.stop_session()
        self.assertTrue(pipeline.disposed)
        self.assertTrue(session.disposed)
        self.assertIsNone(monitor.subscription)


if __name__ == "__main__":
    unittest.main()
