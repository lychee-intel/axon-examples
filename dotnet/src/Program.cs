using System.Windows;
using Axon;

namespace LycheeMonitor;

public sealed record CommandLineArgs(
    string? Serial,
    double WindowSeconds,
    bool NoFilter,
    bool Notch,
    LogLevel LogLevel);

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
        string? serial = null;
        var window = 10.0;
        var noFilter = false;
        var notch = false;
        var logLevel = "off";

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
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
                case "--notch":
                    notch = true;
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

        var level = logLevel switch
        {
            "off" => LogLevel.Off,
            "error" => LogLevel.Error,
            "warn" => LogLevel.Warn,
            "info" => LogLevel.Info,
            "debug" => LogLevel.Debug,
            "trace" => LogLevel.Trace,
            _ => (LogLevel?)null,
        };

        if (level is null)
            return Error($"Invalid log level: {logLevel} (valid: off, error, warn, info, debug, trace)");

        return new CommandLineArgs(serial, window, noFilter, notch, level.Value);
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
              --serial HEX          Connect to a device by its hex serial
              --window SECONDS      Waveform display window (default 10.0)
              --no-filter           Disable the 0.4–70 Hz bandpass filter
              --notch               Add a 50 Hz notch (Q=30) for real hardware
              --log-level LEVEL     Rust log level (off|error|warn|info|debug|trace)
              -h, --help            Show this help message
            """);
    }
}
