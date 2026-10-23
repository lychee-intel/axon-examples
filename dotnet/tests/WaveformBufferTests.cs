using Xunit;
using Axon;
using Axon.Native;

namespace LycheeMonitor.Tests;

public class WaveformBufferTests
{
    [Fact]
    public void SelectUniformEeg_IgnoresIrregularEegAndOtherUniformStreams()
    {
        var streams = new[]
        {
            new DeviceStreamInfo("irregular", "Irregular EEG", (uint)AxonStreamKind.Eeg, 0, 250, 3,
                AxonSamplingMode.Irregular),
            new DeviceStreamInfo("motion", "Motion", (uint)AxonStreamKind.Motion, 0, 50, 6),
            new DeviceStreamInfo("eeg", "EEG", (uint)AxonStreamKind.Eeg, 0, 250, 3),
        };

        Assert.Equal("eeg", CollectionSessionStartup.SelectUniformEeg(streams).Id);
    }

    [Fact]
    public void CreateConfigured_DisposesSessionWhenConfigurationFails()
    {
        var session = new DisposableProbe();

        Assert.Throws<InvalidOperationException>(() => CollectionSessionStartup.CreateConfigured(
            () => session,
            _ => throw new InvalidOperationException("configuration failed")));

        Assert.Equal(1, session.DisposeCount);
    }

    private sealed class DisposableProbe : IDisposable
    {
        public int DisposeCount { get; private set; }
        public void Dispose() => DisposeCount++;
    }

    [Fact]
    public void Append_InterleavedBlock_DeinterleavesChannels()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        buffer.Append(2, 3, 4.0, [1, 10, 2, 20, 3, 30]);

        Assert.Equal([1.0, 2.0, 3.0], buffer.ChannelSamples(0));
        Assert.Equal([10.0, 20.0, 30.0], buffer.ChannelSamples(1));
    }

    [Fact]
    public void SimulatorControl_IsEnabledOnlyAfterAxonStarts()
    {
        Assert.False(SimulatorControlState.CanAddSimulator(
            axonStarted: false,
            simulatorAdded: false,
            isCollecting: false));

        Assert.True(SimulatorControlState.CanAddSimulator(
            axonStarted: true,
            simulatorAdded: false,
            isCollecting: false));

        Assert.False(SimulatorControlState.CanAddSimulator(
            axonStarted: true,
            simulatorAdded: true,
            isCollecting: false));

        Assert.False(SimulatorControlState.CanAddSimulator(
            axonStarted: true,
            simulatorAdded: false,
            isCollecting: true));
    }

    [Fact]
    public void Append_SingleBlock_StoresSamples()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        var data = new float[] { 1f, 10f, 2f, 20f, 3f, 30f }; // interleaved
        buffer.Append(numChannels: 2, numSamples: 3, sampleRateHz: 4.0, data);

        Assert.Equal(2, buffer.ChannelCount);
        Assert.Equal(4.0, buffer.SampleRateHz);
        Assert.Equal([1f, 2f, 3f], buffer.ChannelSamples(0));
        Assert.Equal([10f, 20f, 30f], buffer.ChannelSamples(1));
    }

    [Fact]
    public void Append_MultipleBlocks_EvictsOldData()
    {
        // Window = 1 second at 4 Hz → capacity = 4 samples per channel
        var buffer = new WaveformBuffer(windowSeconds: 1.0);

        // First block: 2 channels × 4 samples (fills the buffer)
        buffer.Append(2, 4, 4.0, [1, 10, 2, 20, 3, 30, 4, 40]);

        // Second block: 2 channels × 3 samples (overflows, old data evicted)
        buffer.Append(2, 3, 4.0, [5, 50, 6, 60, 7, 70]);

        // Channel 0: capacity 4, had [1,2,3,4], appended [5,6,7]
        // After overflow: should keep last 4 → [4, 5, 6, 7]
        Assert.Equal([4.0, 5.0, 6.0, 7.0], buffer.ChannelSamples(0));

        // Channel 1: capacity 4, had [10,20,30,40], appended [50,60,70]
        Assert.Equal([40.0, 50.0, 60.0, 70.0], buffer.ChannelSamples(1));
    }

    [Fact]
    public void Append_ChannelCountChange_Reallocates()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);

        buffer.Append(2, 2, 4.0, [1, 10, 2, 20]);
        Assert.Equal(2, buffer.ChannelCount);

        // Change to 3 channels — buffer reallocates (old data is lost)
        buffer.Append(3, 2, 4.0, [1, 10, 100, 2, 20, 200]);
        Assert.Equal(3, buffer.ChannelCount);
        Assert.Equal([100.0, 200.0], buffer.ChannelSamples(2));
    }

    [Fact]
    public void Clear_ResetsAllState()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        buffer.Append(2, 3, 4.0, [1, 10, 2, 20, 3, 30]);

        buffer.Clear();

        Assert.Equal(0, buffer.ChannelCount);
        Assert.Empty(buffer.ChannelSamples(0));
    }

    [Fact]
    public void ChannelSamples_OutOfRange_ReturnsEmpty()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        Assert.Empty(buffer.ChannelSamples(-1));
        Assert.Empty(buffer.ChannelSamples(99));
    }

    [Fact]
    public void Append_IgnoresZeroChannels()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        buffer.Append(0, 3, 4.0, [1, 2, 3]);
        Assert.Equal(0, buffer.ChannelCount);
    }

    [Fact]
    public void Append_IgnoresZeroSamples()
    {
        var buffer = new WaveformBuffer(windowSeconds: 1.0);
        buffer.Append(2, 0, 4.0, []);
        Assert.Equal(0, buffer.ChannelCount);
    }

    [Fact]
    public void WindowCapacity_RoundsUp()
    {
        // 1.5s * 10Hz = 15 → capacity = 15
        var buffer = new WaveformBuffer(windowSeconds: 1.5);
        var data = new float[15]; // 1 channel × 15 samples
        for (var i = 0; i < 15; i++) data[i] = i;
        buffer.Append(1, 15, 10.0, data);

        Assert.Equal(15, buffer.ChannelSamples(0).Length);

        // One more sample → oldest evicted
        buffer.Append(1, 1, 10.0, [99f]);
        var samples = buffer.ChannelSamples(0);
        Assert.Equal(15, samples.Length);
        Assert.Equal(99.0, samples[^1]);
        Assert.Equal(1.0, samples[0]); // first sample (0) was evicted
    }
}
