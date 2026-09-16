namespace LycheeMonitor;

internal static class SimulatorControlState
{
    public static bool CanAddSimulator(bool axonStarted, bool simulatorAdded, bool isCollecting)
        => axonStarted && !simulatorAdded && !isCollecting;
}
