using System.Collections.Concurrent;

namespace LycheeMonitor;

/// <summary>
/// Thread-safe circular buffer that keeps a fixed-duration sliding window
/// of EEG samples, organized per channel.
/// </summary>
public sealed class WaveformBuffer
{
    private readonly object _lock = new();
    private double[][] _channels = [];
    private int[] _counts = [];
    private int _capacity;

    public double WindowSeconds { get; }
    public double SampleRateHz { get; private set; }
    public int ChannelCount => _channels.Length;

    public WaveformBuffer(double windowSeconds = 5.0)
    {
        WindowSeconds = windowSeconds;
    }

    /// <summary>Clear all buffered data and reset channel state.</summary>
    public void Clear()
    {
        lock (_lock)
        {
            _channels = [];
            _counts = [];
            _capacity = 0;
        }
    }

    /// <summary>
    /// Append a block of samples. Thread-safe — called from the Axon callback thread.
    /// <paramref name="data"/> is channel-major: [ch0_s0, ch0_s1, ..., ch1_s0, ...]
    /// </summary>
    public void Append(int numChannels, int numSamples, double sampleRateHz, float[] data)
    {
        if (numChannels <= 0 || numSamples <= 0) return;

        lock (_lock)
        {
            // Reallocate if channel count or sample rate changed
            if (_channels.Length != numChannels || SampleRateHz != sampleRateHz)
            {
                SampleRateHz = sampleRateHz;
                _capacity = Math.Max(1, (int)Math.Ceiling(WindowSeconds * sampleRateHz));
                _channels = new double[numChannels][];
                _counts = new int[numChannels];
                for (var ch = 0; ch < numChannels; ch++)
                {
                    _channels[ch] = new double[_capacity];
                    _counts[ch] = 0;
                }
            }

            for (var ch = 0; ch < numChannels; ch++)
            {
                var buf = _channels[ch];
                var count = _counts[ch];
                var offset = ch * numSamples;

                for (var i = 0; i < numSamples; i++)
                {
                    if (count < _capacity)
                    {
                        buf[count++] = data[offset + i];
                    }
                    else
                    {
                        // Shift left by 1 and append at end
                        Array.Copy(buf, 1, buf, 0, _capacity - 1);
                        buf[_capacity - 1] = data[offset + i];
                    }
                }
                _counts[ch] = count;
            }
        }
    }

    /// <summary>
    /// Snapshot the samples for a given channel. Returns an empty array if
    /// the channel index is out of range.
    /// </summary>
    public double[] ChannelSamples(int channel)
    {
        lock (_lock)
        {
            if (channel < 0 || channel >= _channels.Length)
                return [];

            var count = _counts[channel];
            var result = new double[count];
            Array.Copy(_channels[channel], result, count);
            return result;
        }
    }
}
