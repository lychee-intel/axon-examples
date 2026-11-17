# Axon .NET Example — Lychee EEG Monitor

[中文](README.zh-CN.md)

WPF desktop application using the Axon 0.10.0 binding (native ABI 0.10.x),
CommunityToolkit.Mvvm and ScottPlot. It selects a uniform EEG stream and reads
its actual sample rate and channel count from the device descriptors.

- **Add Lychee BCI100** starts a vendor simulator with 3 EEG channels at 250 Hz.
- Waveforms scroll with automatic scaling. A 0.4–70 Hz IIR bandpass is enabled
  by default; `--no-filter` disables it and `--notch` adds a 50 Hz notch.
- Stopping collection releases the subscription, pipeline and device Session.
  Discovery continues until the window closes.

## Build and run

Use Windows with the .NET 8 SDK or later, Rust, Python and PowerShell (`pwsh`).
Place `axon` and `axon-examples` next to each other. From this directory:

```powershell
pwsh ../../axon/scripts/build-native.ps1 -Profile debug
dotnet run --project src
dotnet test tests
```

For `dotnet run --project src -c Release`, first build the native bundle with
`-Profile release`. Source mode copies `axon.dll`, `lsl.dll` and `LSL-*.txt` from
`axon/outputs/native/windows/<configuration>/` beside the application. Missing
bundle files fail the build with a preparation command. `AxonNativeDllPath` can
select another complete matching bundle.

The application opens a device Session, selects uniform EEG, creates a processing
pipeline and subscribes to its output. Managed readers feed the WPF Dispatcher.

## Standalone NuGet mode

Without a sibling binding checkout, the application and tests reference `Axon`
0.10.0 from `packages/`. Prepare a matching package from the Axon checkout:

```powershell
$axon = (Resolve-Path ../../axon).Path
pwsh "$axon/scripts/build-native.ps1" -Profile release
dotnet pack "$axon/bindings/dotnet/Axon/Axon.csproj" -c Release `
  "-p:AxonNativeLibDir=$axon/outputs/native/windows/release" `
  -p:AxonNativeRuntimeIdentifier=win-x64 -o ./packages
dotnet restore src --force
dotnet restore tests --force
```

Select `win-arm64` when packaging an ARM64 native build. Keep the Axon and LSL
libraries and license notices together. The local NuGet cache is
`../target/dotnet-nuget-cache`; if replacing a package with the same version,
remove only its `axon/0.10.0` entry before restoring.

## CLI options

| Option | Description |
| --- | --- |
| `--serial HEX` | Select a device by its six-digit hex serial |
| `--window SECONDS` | Display window, default 10 seconds |
| `--no-filter` | Disable the 0.4–70 Hz bandpass |
| `--notch` | Add a 50 Hz notch, Q=30 |
| `--log-level LEVEL` | trace, debug, information, warning, error, critical, none (default) |
| `--help` | Print usage |

Example: `dotnet run --project src -- --serial AABBCC --window 10 --notch`.

The current binding also provides standalone AXF files, offline EEG window/PSD
analysis, native band peaks, transport health and LSL publication. See the
[.NET API guide](../docs/api/dotnet.md) for examples.
