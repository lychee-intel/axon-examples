using System.Globalization;
using System.Windows.Data;

namespace LycheeMonitor;

/// <summary>Inverts a boolean value for XAML binding (true → false, false → true).</summary>
[ValueConversion(typeof(bool), typeof(bool))]
public class InvertBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
        => value is bool b && !b;

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
        => value is bool b && !b;
}
