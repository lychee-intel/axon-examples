# Axon .NET Example — Lychee EEG Monitor

[中文](README.zh-CN.md)

WPF desktop application that displays real-time EEG waveforms from a Lychee device or built-in simulator, using the Axon C# binding and ScottPlot for visualization.

## Features

- **Device discovery** — auto-detects Lychee EEG hardware on the LAN
- **Simulator mode** — `--sim` creates a virtual 3-channel, 250 Hz device
- **Real-time waveforms** — scrolling multi-channel EEG display with auto-scaling
- **0.4–70 Hz bandpass filter** — single-section IIR filter applied by default, matching the native debugger (`--no-filter` to disable, `--notch` to add a 50 Hz notch)
- **Dark theme** — matches the Python example's visual style

## Prerequisites

- .NET 8.0+ SDK

The `Axon` NuGet package (including the native `axon.dll`) is included in `dotnet/packages/`.
To rebuild it from the `axon` repo:

## Running

```bash
# Simulator mode (no hardware needed)
dotnet run --project src -- --sim

# With a known device serial
dotnet run --project src -- --serial AABBCC

# Custom window duration and no filter
dotnet run --project src -- --sim --window 10 --no-filter

# Show help
dotnet run --project src -- --help
```

## CLI Options

| Option              | Description                                          |
| ------------------- | ---------------------------------------------------- |
| `--sim`             | Use the built-in simulator (no hardware)             |
| `--serial HEX`      | Add a device by its 6-char hex serial                |
| `--window SECONDS`  | Waveform display window (default 10.0)               |
| `--no-filter`       | Disable the 0.4–70 Hz bandpass filter                |
| `--notch`           | Add a 50 Hz notch (Q=30), useful with real hardware  |
| `--log-level LEVEL` | Rust log level: off, error, warn, info, debug, trace |

## Building

```bash
dotnet build src
dotnet test tests
```

## Project Structure

```
dotnet/
├── LycheeMonitor.sln
├── nuget.config                   # Local NuGet feed pointing to packages/
├── packages/
│   └── Axon.0.1.0.nupkg          # Axon binding NuGet package (with native lib)
├── src/
│   ├── LycheeMonitor.csproj       # WPF app (net8.0-windows)
│   ├── Program.cs                 # Entry point + CLI arg parsing
│   ├── MainWindow.xaml            # WPF layout (XAML)
│   ├── MainWindow.xaml.cs         # Application logic + ScottPlot rendering
│   └── WaveformBuffer.cs          # Thread-safe circular sample buffer
└── tests/
    ├── WaveformBufferTests.csproj
    └── WaveformBufferTests.cs     # Unit tests for WaveformBuffer
```
