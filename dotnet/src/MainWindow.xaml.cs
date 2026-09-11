using System.Windows;

namespace LycheeMonitor;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    public MainWindow(CommandLineArgs args)
    {
        InitializeComponent();

        // Give the ViewModel the Plot from the WPF control
        _vm = new MainViewModel(args, PlotView.Plot, MessageBox.Show);
        DataContext = _vm;

        _vm.PlotUpdated += () => PlotView.Refresh();

        Closing += (_, _) => _vm.Dispose();
    }
}
