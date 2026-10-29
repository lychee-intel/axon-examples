using Axon.Data;
using Axon.Devices;


namespace LycheeMonitor;

internal static class CollectionSessionStartup
{
    internal static DeviceStreamInfo SelectUniformEeg(IEnumerable<DeviceStreamInfo> streams)
    {
        return streams.FirstOrDefault(stream =>
            stream.Kind == StreamKind.Eeg &&
            stream.SamplingMode == SamplingMode.Uniform)
            ?? throw new InvalidOperationException("Device has no uniformly sampled EEG stream.");
    }

    internal static T CreateConfigured<T>(Func<T> create, Action<T> configure)
        where T : IDisposable
    {
        var session = create();
        try
        {
            configure(session);
            return session;
        }
        catch
        {
            session.Dispose();
            throw;
        }
    }
}
