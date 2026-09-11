using System.Windows;
using Axon.Native;

namespace LycheeMonitor;

public sealed record CommandLineArgs(
    bool Sim,
    string? Serial,
    double WindowSeconds,
    bool NoFilter,
    uint LogLevel);

internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        var parsed = ParseArgs(args);
        if (parsed is null) return;

        var app = new Application();
        app.ShutdownMode = ShutdownMode.OnMainWindowClose;
        var window = new MainWindow(parsed);
        app.Run(window);
    }

    private static CommandLineArgs? ParseArgs(string[] args)
    {
        var sim = false;
        string? serial = null;
        var window = 5.0;
        var noFilter = false;
        var logLevel = "off";

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--sim":
                    sim = true;
                    break;
                case "--serial":
                    if (i + 1 >= args.Length) return Error("--serial requires a HEX argument");
                    serial = args[++i];
                    break;
                case "--window":
                    if (i + 1 >= args.Length) return Error("--window requires a numeric argument");
                    if (!double.TryParse(args[++i], out window) || window <= 0)
                        return Error("--window must be greater than 0");
                    break;
                case "--no-filter":
                    noFilter = true;
                    break;
                case "--log-level":
                    if (i + 1 >= args.Length) return Error("--log-level requires a level argument");
                    logLevel = args[++i].ToLowerInvariant();
                    break;
                case "--help" or "-h":
                    PrintUsage();
                    return null;
                default:
                    return Error($"Unknown argument: {args[i]}");
            }
        }

        if (sim && serial is not null)
            return Error("--sim and --serial cannot be used together");

        var level = logLevel switch
        {
            "off" => AxonLogLevel.Off,
            "error" => AxonLogLevel.Error,
            "warn" => AxonLogLevel.Warn,
            "info" => AxonLogLevel.Info,
            "debug" => AxonLogLevel.Debug,
            "trace" => AxonLogLevel.Trace,
            _ => (uint?)null,
        };

        if (level is null)
            return Error($"Invalid log level: {logLevel} (valid: off, error, warn, info, debug, trace)");

        return new CommandLineArgs(sim, serial, window, noFilter, level.Value);
    }

    private static CommandLineArgs? Error(string message)
    {
        Console.Error.WriteLine($"error: {message}");
        Console.Error.WriteLine();
        PrintUsage();
        return null;
    }

    private static void PrintUsage()
    {
        Console.WriteLine("""
            Usage: LycheeMonitor [options]

            Lychee EEG real-time waveform monitor

            Options:
              --sim                 Use built-in simulator (no hardware needed)
              --serial HEX          Connect to a device by its hex serial
              --window SECONDS      Waveform display window (default 5.0)
              --no-filter           Disable 50 Hz notch filter
              --log-level LEVEL     Rust log level (off|error|warn|info|debug|trace)
              -h, --help            Show this help message
            """);
    }
}
