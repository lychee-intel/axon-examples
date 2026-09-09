"""Tests for the data model used by the Tk Lychee monitor example."""

import sys
import unittest
from pathlib import Path

from axon import SampleBlock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lychee_monitor import WaveformBuffer


class TestWaveformBuffer(unittest.TestCase):
    def test_retains_only_the_latest_window_for_each_channel(self):
        """A monitor redraw must not retain samples older than its visible window."""
        buffer = WaveformBuffer(window_seconds=1.0)
        buffer.append(SampleBlock(
            start_timestamp=0,
            sample_rate_hz=4.0,
            num_channels=2,
            num_samples=4,
            data=[1, 2, 3, 4, 10, 20, 30, 40],
        ))
        buffer.append(SampleBlock(
            start_timestamp=1_000_000,
            sample_rate_hz=4.0,
            num_channels=2,
            num_samples=4,
            data=[5, 6, 7, 8, 50, 60, 70, 80],
        ))

        self.assertEqual(buffer.channel_samples(0), [5, 6, 7, 8])
        self.assertEqual(buffer.channel_samples(1), [50, 60, 70, 80])
        self.assertEqual(buffer.sample_rate_hz, 4.0)


if __name__ == "__main__":
    unittest.main()
