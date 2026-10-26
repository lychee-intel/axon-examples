using System.Windows;

namespace LycheeMonitor;

public sealed record CustomSimulatorRequest(string Serial, int EegChannels, bool NirsEnabled);

public partial class CustomSimulatorDialog : Window
{
    public CustomSimulatorRequest? Request { get; private set; }

    public CustomSimulatorDialog()
    {
        InitializeComponent();
        SerialBox.Focus();
        SerialBox.SelectAll();
    }

    private void Add_Click(object sender, RoutedEventArgs e)
    {
        var serial = SerialBox.Text.Trim();
        if (serial.Length != 6 || !serial.All(Uri.IsHexDigit))
        {
            ErrorText.Text = "Enter a 6-character hexadecimal serial.";
            return;
        }

        if (!int.TryParse(EegChannelsBox.Text, out var eegChannels) || eegChannels is < 0 or > 64)
        {
            ErrorText.Text = "EEG channels must be a number from 0 to 64.";
            return;
        }

        var nirsEnabled = NirsCheckBox.IsChecked == true;
        if (eegChannels == 0 && !nirsEnabled)
        {
            ErrorText.Text = "Enable EEG or NIRS to create a simulator.";
            return;
        }

        Request = new CustomSimulatorRequest(serial, eegChannels, nirsEnabled);
        DialogResult = true;
    }
}
