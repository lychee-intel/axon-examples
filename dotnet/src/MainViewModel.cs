using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Threading;
using Axon;
using Axon.Native;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ScottPlot;
using ScottPlot.Plottables;

namespace LycheeMonitor;

public partial class MainViewModel : ObservableObject, IDisposable
{
    private const string SimSerial = "lychee-sim";

    private readonly CommandLineArgs _args;
    private readonly Axon.Axon _axon;
    private readonly WaveformBuffer _buffer;
    private readonly ConcurrentQueue<DeviceEventArgs> _deviceEvents = new();
    private readonly Dictionary<string, string> _deviceMap = new();
    private readonly DispatcherTimer _timer;
    private AxonSession? _session;
    private bool _disposed;

    // ── Dialog service (injected by View) ────────────────────────────────────

    private readonly Func<string, string, MessageBoxButton, MessageBoxImage, MessageBoxResult>? _showDialog;

    // ── Observable properties ────────────────────────────────────────────────

    [ObservableProperty]
    private string _statusText = "";

    [ObservableProperty]
    private string _footerText = "";

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartCollectionCommand))]
    private string? _selectedDevice;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartCollectionCommand))]
    [NotifyCanExecuteChangedFor(nameof(StopCollectionCommand))]
    private bool _isCollecting;

    // ── Chart ────────────────────────────────────────────────────────────────

    public Plot Plot { get; }

    /// <summary>Raised after the chart has been re-rendered; View should call FormsPlot.Refresh().</summary>
    public event Action? PlotUpdated;

    // ── Device list ──────────────────────────────────────────────────────────

    public ObservableCollection<string> Devices { get; } = [];

    // ── Constructor ──────────────────────────────────────────────────────────

    public MainViewModel(
        CommandLineArgs args,
        Plot plot,
        Func<string, string, MessageBoxButton, MessageBoxImage, MessageBoxResult>? showDialog = null)
    {
        _args = args;
        _showDialog = showDialog;
        Plot = plot;

        FooterText = $"Last {args.WindowSeconds:F1}s  ·  Grid 0.5s  ·  Auto-scale";

        RebuildChart(0, 0);

        _axon = new Axon.Axon();
        _buffer = new WaveformBuffer(args.WindowSeconds);

        Axon.Axon.LogInit(args.LogLevel);
        _axon.SetDeviceCallback(ev => _deviceEvents.Enqueue(ev));
        StartListener();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _timer.Tick += OnTimerTick;
        _timer.Start();
    }

    // ── Listener ─────────────────────────────────────────────────────────────

    private void StartListener()
    {
        try
        {
            if (_args.Sim)
            {
                _axon.Start();
                _axon.AddSimulator(SimSerial, numChannels: 3, sampleRateHz: 250.0);
                StatusText = "Simulator ready, select lychee-sim to start";
            }
            else
            {
                _axon.Start();
                if (_args.Serial is { } serial)
                {
                    AddDevice(serial, "Specified sensor");
                    StatusText = "Sensor specified, select to start";
                }
                else
                {
                    StatusText = "Listening on TCP:31200 / UDP:31300 / Multicast 239.0.0.6:31400";
                }
            }
        }
        catch (AxonException ex)
        {
            StatusText = $"Listener failed: {ex.Message}";
            _showDialog?.Invoke(ex.Message, "Lychee listener failed",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    // ── Timer tick ───────────────────────────────────────────────────────────

    private void OnTimerTick(object? sender, EventArgs e)
    {
        // Drain device events
        while (_deviceEvents.TryDequeue(out var ev))
        {
            if (ev.Connected) AddDevice(ev.Serial, ev.Name);
            else RemoveDevice(ev.Serial);
        }

        // Drain data queue
        if (_session is { } session)
        {
            for (var i = 0; i < 64; i++)
            {
                if (!session.Data.TryRead(out var block)) break;
                _buffer.Append(
                    (int)block.NumChannels,
                    (int)block.NumSamples,
                    block.SampleRateHz,
                    block.Data);
            }
        }

        if (RenderChart())
            PlotUpdated?.Invoke();
    }

    // ── Device management ────────────────────────────────────────────────────

    private void AddDevice(string serial, string name)
    {
        if (string.IsNullOrEmpty(serial)) return;
        var label = $"{serial}  ·  {name ?? "Lychee"}";
        _deviceMap[serial] = label;

        if (!Devices.Contains(label))
            Devices.Add(label);

        SelectedDevice ??= label;

        if (_session is null)
            StatusText = $"Sensor {serial} found, select to start";
    }

    private void RemoveDevice(string serial)
    {
        if (!_deviceMap.TryGetValue(serial, out var label)) return;
        _deviceMap.Remove(serial);
        Devices.Remove(label);

        if (SelectedDevice == label && _session is null)
        {
            SelectedDevice = Devices.FirstOrDefault();
            StatusText = $"Sensor {serial} went offline";
        }
    }

    private string? ResolveSerial()
    {
        return _deviceMap.FirstOrDefault(kv => kv.Value == SelectedDevice).Key;
    }

    // ── Start collection ─────────────────────────────────────────────────────

    [RelayCommand(CanExecute = nameof(CanStartCollection))]
    private void StartCollection()
    {
        var serial = ResolveSerial();
        if (serial is null)
        {
            _showDialog?.Invoke("Please select a discovered Lychee sensor first.",
                "Select sensor", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        try
        {
            var info = _axon.DeviceInfo(serial);
            var session = _axon.NewSession(serial);

            if (!_args.NoFilter)
            {
                // The FFI requires an explicit Q (0 is rejected), so compute the
                // same value the native side would auto-derive: q = f0 / bandwidth.
                const double bpLow = 0.4, bpHigh = 70.0;
                var bpQ = Math.Sqrt(bpLow * bpHigh) / (bpHigh - bpLow);
                session.AddFilter(new FilterStageConfig(
                    FilterType: AxonFilterType.Iir,
                    Kind: AxonFilterKind.BandPass,
                    CutoffHz: bpLow,
                    Cutoff2Hz: bpHigh,
                    Order: 2,
                    Q: bpQ,
                    SampleRateHz: info.SampleRateHz));
            }

            _session = session;
            _buffer.Clear();
            IsCollecting = true;
            StatusText = _args.NoFilter
                ? $"Collecting {serial} · {info.NumChannels} ch · {info.SampleRateHz:F0} Hz · unfiltered"
                : $"Collecting {serial} · {info.NumChannels} ch · {info.SampleRateHz:F0} Hz · BP 0.4–70 Hz";
        }
        catch (AxonException ex)
        {
            _showDialog?.Invoke(ex.Message, "Failed to start collection",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private bool CanStartCollection() => !IsCollecting && SelectedDevice is not null;

    // ── Stop collection ──────────────────────────────────────────────────────

    [RelayCommand(CanExecute = nameof(CanStopCollection))]
    private void StopCollection()
    {
        try
        {
            _session?.Dispose();
        }
        catch { /* best-effort */ }

        _session = null;
        _buffer.Clear();
        IsCollecting = false;
        StatusText = SelectedDevice is not null
            ? "Stopped, select Start to resume"
            : "Stopped";
    }

    private bool CanStopCollection() => IsCollecting;

    // ── Chart rendering ──────────────────────────────────────────────────────

    /// <summary>Persistent per-channel plottables, rebuilt only when the channel
    /// count or sample rate changes — per-tick updates mutate them in place.</summary>
    private sealed class ChannelVisual
    {
        public required Signal Signal;
        public required Text ChLabel;
        public required Text AmpLabel;
        public required HorizontalLine Center;
        public HorizontalLine? Sep;
        public double[] Ys = [];
        public double LastAmplitude = -1;
    }

    private ChannelVisual[] _channelVisuals = [];
    private Text? _waitingText;
    private int _builtChannels = -1;
    private int _builtCapacity;

    private void RebuildChart(int channels, int capacity)
    {
        Plot.Clear();
        _channelVisuals = [];
        _waitingText = null;
        _builtChannels = channels;
        _builtCapacity = capacity;

        Plot.FigureBackground.Color = Color.FromHex("#07120d");
        Plot.DataBackground.Color = Color.FromHex("#07120d");
        Plot.Legend.IsVisible = false;
        Plot.Axes.Left.IsVisible = false;
        Plot.Axes.Bottom.Label.Text = "Time (s)";
        Plot.Axes.Bottom.Label.ForeColor = Color.FromHex("#6da886");
        Plot.Axes.Bottom.Label.FontSize = 11;
        Plot.Axes.Bottom.MajorTickStyle.Color = Color.FromHex("#2b6245");
        Plot.Axes.Bottom.TickLabelStyle.ForeColor = Color.FromHex("#6da886");
        Plot.Axes.SetLimitsX(0, _args.WindowSeconds);
        Plot.Axes.SetLimitsY(-1, 1);

        if (channels == 0)
        {
            var tp = Plot.Add.Text("Waiting for sensor data…", _args.WindowSeconds * 0.5, 0);
            tp.LabelFontColor = Color.FromHex("#80a897");
            tp.LabelFontSize = 18;
            tp.LabelAlignment = Alignment.MiddleCenter;
            _waitingText = tp;
            return;
        }

        for (var t = 0.5; t < _args.WindowSeconds; t += 0.5)
        {
            var vl = Plot.Add.VerticalLine(t);
            vl.Color = Color.FromHex("#17432e");
            vl.LineWidth = 0.5f;
        }

        for (var ch = 0; ch < channels; ch++)
        {
            var ys = new double[Math.Max(capacity, 1)];
            var sp = Plot.Add.Signal(ys);
            sp.Color = Color.FromHex("#42ef9c");
            sp.LineWidth = 1.4f;
            sp.MinRenderIndex = 0;
            sp.MaxRenderIndex = 0;

            var chLabel = Plot.Add.Text($"CH {ch + 1}", 0.1, 0);
            chLabel.LabelFontColor = Color.FromHex("#93cdb1");
            chLabel.LabelFontSize = 12;
            chLabel.LabelBold = true;
            chLabel.LabelAlignment = Alignment.UpperLeft;

            var ampLabel = Plot.Add.Text("", _args.WindowSeconds - 0.1, 0);
            ampLabel.LabelFontColor = Color.FromHex("#6da886");
            ampLabel.LabelFontSize = 11;
            ampLabel.LabelAlignment = Alignment.UpperRight;

            var center = Plot.Add.HorizontalLine(0);
            center.Color = Color.FromHex("#2b6245");
            center.LineWidth = 0.8f;

            HorizontalLine? sep = null;
            if (ch > 0)
            {
                sep = Plot.Add.HorizontalLine(0);
                sep.Color = Color.FromHex("#17432e");
                sep.LineWidth = 0.5f;
            }

            _channelVisuals = [.. _channelVisuals, new ChannelVisual
            {
                Signal = sp,
                ChLabel = chLabel,
                AmpLabel = ampLabel,
                Center = center,
                Sep = sep,
                Ys = ys,
            }];
        }
    }

    /// <summary>Update chart visuals in place. Returns true if anything changed
    /// and the view should refresh.</summary>
    private bool RenderChart()
    {
        var channels = _buffer.ChannelCount;
        var rate = _buffer.SampleRateHz;
        var capacity = rate > 0 ? Math.Max(1, (int)Math.Ceiling(_args.WindowSeconds * rate)) : 0;

        if (channels != _builtChannels || capacity != _builtCapacity)
        {
            RebuildChart(channels, capacity);
            return true;
        }

        if (channels == 0 || rate <= 0)
            return false;

        var period = 1.0 / rate;
        double yMinGlobal = double.MaxValue, yMaxGlobal = double.MinValue;

        for (var ch = 0; ch < channels; ch++)
        {
            var samples = _buffer.ChannelSamples(ch);
            var vis = _channelVisuals[ch];
            var count = Math.Min(samples.Length, vis.Ys.Length);
            if (count > 0)
                Array.Copy(samples, vis.Ys, count);

            double amplitude = 50;
            for (var i = 0; i < count; i++)
            {
                var v = Math.Abs(samples[i]);
                if (v > amplitude) amplitude = v;
            }
            var offset = (2 * ch + 1) * amplitude * 1.15;

            vis.Signal.Data.YOffset = offset;
            vis.Signal.Data.Period = period;
            vis.Signal.Data.XOffset = _args.WindowSeconds - count * period;
            vis.Signal.MinRenderIndex = 0;
            vis.Signal.MaxRenderIndex = Math.Max(0, count - 1);
            vis.Signal.IsVisible = count >= 2;

            var labelY = offset + amplitude * 0.9;
            vis.ChLabel.Location = new Coordinates(0.1, labelY);
            vis.AmpLabel.Location = new Coordinates(_args.WindowSeconds - 0.1, labelY);
            if (amplitude != vis.LastAmplitude)
            {
                vis.AmpLabel.LabelText = $"±{amplitude:F0} µV";
                vis.LastAmplitude = amplitude;
            }

            vis.Center.Y = offset;
            if (vis.Sep is { } sep)
                sep.Y = offset - amplitude * 1.15;

            var laneBottom = offset - amplitude * 1.15;
            var laneTop = offset + amplitude * 1.15;
            if (laneBottom < yMinGlobal) yMinGlobal = laneBottom;
            if (laneTop > yMaxGlobal) yMaxGlobal = laneTop;
        }

        if (yMinGlobal < yMaxGlobal)
            Plot.Axes.SetLimitsY(yMinGlobal, yMaxGlobal);

        return true;
    }

    // ── Disposal ─────────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _timer.Stop();

        try
        {
            _session?.Dispose();
            _axon.Dispose();
        }
        catch { /* best-effort */ }
    }
}
