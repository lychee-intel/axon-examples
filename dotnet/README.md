# Axon .NET Example — Lychee EEG Monitor

[中文](README.zh-CN.md)

WPF desktop application that displays real-time EEG waveforms from a Lychee device or built-in Lychee PFC simulator, using the Axon C# binding and ScottPlot for visualization.

## Features

- **Device discovery** — auto-detects Lychee EEG hardware on the LAN
- **Simulator** — click **Add simulator** after Axon starts to create a virtual 3-channel, 250 Hz device
- **Real-time waveforms** — scrolling multi-channel EEG display with auto-scaling
- **0.4–70 Hz bandpass filter** — single-section IIR filter applied by default, matching the native debugger (`--no-filter` to disable, `--notch` to add a 50 Hz notch)
- **Dark theme** — matches the Python example's visual style

## Prerequisites

- .NET 8.0+ SDK

The example targets the Axon C# binding and C ABI 0.2. Its NuGet package includes the matching native `axon.dll`. When the `axon` and `axon-examples` repositories share a parent directory, the project defaults to the binding source at `axon/bindings/dotnet/Axon`; standalone checkouts use the local NuGet feed, which pins `Axon` to `packages/` and keeps the global package cache under `../target/dotnet-nuget-cache-abi020`.

In local source mode, build the native library for the selected configuration in the `axon` repository before running. The example copies that library beside the app so it cannot accidentally load another system `axon.dll`.

```powershell
cargo build -p axon-ffi
```

From this directory, rebuild the package from the sibling `axon` checkout on Windows PowerShell:

```powershell
$axon = (Resolve-Path ..\..\axon).Path
cargo build --manifest-path "$axon\Cargo.toml" -p axon-ffi --release
$stage = Join-Path $PWD '..\target\axon-package-abi020'
$native = Join-Path $stage 'win-x64\native'
New-Item -ItemType Directory -Force $native | Out-Null
Copy-Item "$axon\target\release\axon.dll" (Join-Path $native 'axon.dll') -Force
dotnet pack (Join-Path $axon 'bindings\dotnet\Axon\Axon.csproj') -c Release "-p:AxonNativeLibDir=$stage" -o .\packages
dotnet restore src --force --no-http-cache
dotnet restore tests --force --no-http-cache
```

The sample selects a uniformly sampled EEG stream explicitly. When replacing an existing package with the same version, remove only `../target/dotnet-nuget-cache-abi020/axon/0.2.0` before restoring so NuGet reads the new local package.

## Running

```bash
# Start the app, then click Add simulator (no hardware needed)
dotnet run --project src

# With a known device serial
dotnet run --project src -- --serial AABBCC

# Custom window duration and no filter
dotnet run --project src -- --window 10 --no-filter

# Show help
dotnet run --project src -- --help
```

## CLI Options

| Option              | Description                                          |
| ------------------- | ---------------------------------------------------- |
| `--serial HEX`      | Add a device by its 6-char hex serial                |
| `--window SECONDS`  | Waveform display window (default 10.0)               |
| `--no-filter`       | Disable the 0.4–70 Hz bandpass filter                |
| `--notch`           | Add a 50 Hz notch (Q=30), useful with real hardware  |
| `--log-level LEVEL` | Minimum log severity: trace, debug, information, warning, error, critical, none (default) |

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
│   └── Axon.0.2.0.nupkg          # Axon binding NuGet package (with native lib)
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
