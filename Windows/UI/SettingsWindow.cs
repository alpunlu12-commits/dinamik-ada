using System;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using DinamikAda.Core;
using Localization = DinamikAda.Core.Localization;
using DinamikAda.Island;
using DinamikAda.Monitors;

namespace DinamikAda.UI;

/// <summary>Ayarlar penceresi (macOS sürümündeki SettingsView'ın bölümleri).</summary>
public sealed class SettingsWindow : Window
{
    private static SettingsWindow? _open;

    /// <summary>Tek pencere: açıksa öne getir.</summary>
    public static void ShowSingle()
    {
        if (_open != null)
        {
            if (_open.WindowState == WindowState.Minimized) _open.WindowState = WindowState.Normal;
            _open.Activate();
            return;
        }
        _open = new SettingsWindow();
        _open.Closed += (_, _) => _open = null;
        _open.Show();
        _open.Activate();
    }

    private readonly AppState _s = AppState.Shared;
    private IslandModel? Model => App.Controller?.Model;
    private TextBlock? _calendarStatus, _mediaStatus, _launchError;

    private SettingsWindow()
    {
        Width = 520;
        Height = 760;
        MinWidth = 460;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = Res("Background");
        Foreground = Res("TextPrimary");
        FontFamily = (FontFamily)FindResource("UiFont");
        FontSize = 13;
        Icon = new System.Windows.Media.Imaging.BitmapImage(new Uri("pack://application:,,,/Assets/AppIcon.ico"));

        Build();
        _s.PropertyChanged += OnSettingsChanged;
        if (Model != null) Model.PropertyChanged += OnModelChanged;
        Closed += (_, _) =>
        {
            _s.PropertyChanged -= OnSettingsChanged;
            if (Model != null) Model.PropertyChanged -= OnModelChanged;
        };
    }

    private void OnSettingsChanged(object? sender, PropertyChangedEventArgs e)
    {
        // Dil değişince bütün metinler yeniden okunur; yeniden başlatma gerekmez.
        if (e.PropertyName == nameof(AppState.Language)) Build();
        else if (e.PropertyName == nameof(AppState.LaunchAtLoginError)) RefreshStatus();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(IslandModel.CalendarStatus) or nameof(IslandModel.CalendarError) or nameof(IslandModel.MediaAvailable))
            RefreshStatus();
    }

    private Brush Res(string key) => (Brush)FindResource(key);

    private void Build()
    {
        Title = Strings.SettingsTitle;
        var root = new DockPanel();

        var header = new Grid { Margin = new Thickness(20) };
        header.Children.Add(new TextBlock { Text = Strings.SettingsTitle, FontSize = 18, FontWeight = FontWeights.Bold });
        var done = new Button { Content = Strings.Done, Style = (Style)FindResource("SmallButton"), HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0), IsCancel = true };
        done.Click += (_, _) => Close();
        header.Children.Add(done);
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);
        var line = new Border { Height = 1, Background = Res("Stroke") };
        DockPanel.SetDock(line, Dock.Top);
        root.Children.Add(line);

        var body = new StackPanel { Margin = new Thickness(20) };
        body.Children.Add(ModulesSection());
        body.Children.Add(AppearanceSection());
        body.Children.Add(BehaviourSection());
        body.Children.Add(GeneralSection());
        root.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Content = root;
        RefreshStatus();
    }

    private void RefreshStatus()
    {
        var model = Model;
        if (_calendarStatus != null && model != null)
        {
            (_calendarStatus.Text, _calendarStatus.Foreground) = model.CalendarStatus switch
            {
                CalendarStatus.Connected => (Strings.CalendarStatusOk, Res("Safe")),
                CalendarStatus.Failed => (Strings.CalendarStatusFailed(model.CalendarError), Res("Arming")),
                _ => (Strings.CalendarStatusNone, Res("TextSecondary")),
            };
        }
        if (_mediaStatus != null && model != null)
        {
            _mediaStatus.Text = model.MediaAvailable ? Strings.MediaActive : Strings.MediaUnavailable;
            _mediaStatus.Foreground = Res(model.MediaAvailable ? "Safe" : "Arming");
        }
        if (_launchError != null)
        {
            _launchError.Text = _s.LaunchAtLoginError ?? "";
            _launchError.Visibility = _s.LaunchAtLoginError == null ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    // MARK: Yapı taşları

    private StackPanel Section(string title, params UIElement[] content)
    {
        var outer = new StackPanel { Margin = new Thickness(0, 0, 0, 24) };
        outer.Children.Add(new TextBlock { Text = Localization.Upper(title), FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Res("TextSecondary"), Margin = new Thickness(4, 0, 0, 8) });
        var inner = new StackPanel();
        foreach (var c in content)
        {
            if (c is FrameworkElement fe && fe.Margin == default) fe.Margin = new Thickness(0, 0, 0, 12);
            inner.Children.Add(c);
        }
        if (inner.Children.Count > 0 && inner.Children[^1] is FrameworkElement last) last.Margin = new Thickness(0);
        outer.Children.Add(new Border { Style = (Style)FindResource("Card"), Padding = new Thickness(14), Child = inner });
        return outer;
    }

    private TextBlock Note(string text) => new() { Text = text, Style = (Style)FindResource("Secondary"), FontSize = 11 };

    private Binding Bind(string path) => new(path) { Source = _s, Mode = BindingMode.TwoWay, UpdateSourceTrigger = UpdateSourceTrigger.PropertyChanged };

    private CheckBox Switch(string label, string path)
    {
        var c = new CheckBox { Style = (Style)FindResource("Switch"), Content = label };
        c.SetBinding(System.Windows.Controls.Primitives.ToggleButton.IsCheckedProperty, Bind(path));
        return c;
    }

    private FrameworkElement ShowWhen(FrameworkElement e, string path)
    {
        e.SetBinding(VisibilityProperty, new Binding(path) { Source = _s, Converter = new BooleanToVisibilityConverter() });
        return e;
    }

    private Grid Labeled(string label, UIElement value)
    {
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(value, 1);
        g.Children.Add(value);
        return g;
    }

    private ComboBox Picker<T>((T Value, string Label)[] options, T current, Action<T> set)
    {
        var box = new ComboBox { MinWidth = 180 };
        foreach (var (_, label) in options) box.Items.Add(label);
        box.SelectedIndex = Math.Max(0, Array.FindIndex(options, o => Equals(o.Value, current)));
        box.SelectionChanged += (_, _) => { if (box.SelectedIndex >= 0) set(options[box.SelectedIndex].Value); };
        return box;
    }

    // MARK: Bölümler

    private StackPanel ModulesSection()
    {
        var link = new TextBox { Margin = new Thickness(0, 4, 0, 0) };
        link.SetBinding(TextBox.TextProperty, new Binding(nameof(AppState.CalendarUrl)) { Source = _s, Mode = BindingMode.TwoWay, UpdateSourceTrigger = UpdateSourceTrigger.LostFocus });
        _calendarStatus = new TextBlock { FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 6) };
        var calendar = new StackPanel();
        calendar.Children.Add(new TextBlock { Text = Strings.CalendarLink, FontSize = 12, Foreground = Res("TextSecondary") });
        calendar.Children.Add(link);
        calendar.Children.Add(_calendarStatus);
        calendar.Children.Add(Note(Strings.CalendarHint));

        _mediaStatus = new TextBlock();

        return Section(Strings.Modules,
            Switch(Strings.NowPlaying, nameof(AppState.MusicEnabled)),
            Switch(Strings.Volume, nameof(AppState.VolumeEnabled)),
            Switch(Strings.Brightness, nameof(AppState.BrightnessEnabled)),
            Switch(Strings.Battery, nameof(AppState.BatteryEnabled)),
            Switch(Strings.Timer, nameof(AppState.TimerEnabled)),
            Switch(Strings.BluetoothDevices, nameof(AppState.BluetoothEnabled)),
            Switch(Strings.CameraMicrophone, nameof(AppState.PrivacyEnabled)),
            Switch(Strings.FileShelf, nameof(AppState.ShelfEnabled)),
            Switch(Strings.Downloads, nameof(AppState.DownloadsEnabled)),
            ShowWhen(Note(Strings.DownloadsHint), nameof(AppState.DownloadsEnabled)),
            Switch(Strings.Calendar, nameof(AppState.CalendarEnabled)),
            ShowWhen(calendar, nameof(AppState.CalendarEnabled)),
            Labeled(Strings.SystemWideMedia, _mediaStatus),
            Note(Strings.MediaHint));
    }

    private StackPanel AppearanceSection()
    {
        var displays = Displays.All();
        var options = new (string, string)[] { ("automatic", Strings.Automatic) }
            .Concat(displays.Select(d => ("display:" + d.Id, d.Name))).ToArray();
        var current = options.Any(o => o.Item1 == _s.PreferredDisplay) ? _s.PreferredDisplay : "automatic";

        var slider = new Slider { Minimum = 0, Maximum = 5, TickFrequency = 0.25, IsSnapToTickEnabled = true, Margin = new Thickness(0, 6, 0, 0) };
        slider.SetBinding(System.Windows.Controls.Primitives.RangeBase.ValueProperty, Bind(nameof(AppState.AutoCollapseDelay)));
        var hint = Note(Strings.AutoCollapseHint(_s.AutoCollapseDelay));
        slider.ValueChanged += (_, e) => hint.Text = Strings.AutoCollapseHint(e.NewValue);
        var collapse = new StackPanel();
        collapse.Children.Add(new TextBlock { Text = Strings.AutoCollapseDelay });
        collapse.Children.Add(slider);
        hint.Margin = new Thickness(0, 4, 0, 0);
        collapse.Children.Add(hint);

        return Section(Strings.Appearance,
            Labeled(Strings.Display, Picker(options, current, v => _s.PreferredDisplay = v)),
            Note(Strings.DisplayHint),
            Labeled(Strings.IslandSizeLabel, Picker(new[] { (IslandSize.Small, Strings.Small), (IslandSize.Medium, Strings.Medium) },
                _s.IslandSize, v => _s.IslandSize = v)),
            Labeled(Strings.AnimationSpeedLabel, Picker(new[] { (AnimationSpeed.Slow, Strings.Slow), (AnimationSpeed.Normal, Strings.Normal), (AnimationSpeed.Fast, Strings.Fast) },
                _s.AnimationSpeed, v => _s.AnimationSpeed = v)),
            collapse);
    }

    private StackPanel BehaviourSection() => Section(Strings.Behaviour,
        Switch(Strings.MediaKeys, nameof(AppState.MediaKeysEnabled)),
        Note(Strings.MediaKeysHint),
        Switch(Strings.HideWhenFullscreen, nameof(AppState.HideWhenFullscreen)),
        Note(Strings.HideWhenFullscreenHint),
        Switch(Strings.HideInScreenshots, nameof(AppState.HideInScreenshots)),
        Note(Strings.HideInScreenshotsHint));

    private StackPanel GeneralSection()
    {
        _launchError = new TextBlock { FontSize = 11, Foreground = Res("Arming"), TextWrapping = TextWrapping.Wrap };
        return Section(Strings.General,
            Labeled(Strings.LanguageLabel, Picker(new[] { (AppLanguage.English, Localization.Label(AppLanguage.English)), (AppLanguage.Turkish, Localization.Label(AppLanguage.Turkish)) },
                _s.Language, v => _s.Language = v)),
            Switch(Strings.SnapLevels, nameof(AppState.SnapLevelsToFivePercent)),
            Note(Strings.SnapLevelsHint),
            Switch(Strings.SoundEffects, nameof(AppState.SoundEffectsEnabled)),
            Note(Strings.SoundEffectsHint),
            Switch(Strings.LaunchAtLogin, nameof(AppState.LaunchAtLogin)),
            _launchError);
    }
}
