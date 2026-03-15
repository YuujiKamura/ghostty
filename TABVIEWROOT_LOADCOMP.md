# TabView Runtime Refactoring: LoadComponent

`tabview_runtime.zig` has been refactored to use `LoadComponent` with `TabViewRoot.xbf` instead of manual element creation.

## Changes
- Added re-exports for `IUriRuntimeClass` and `IUriRuntimeClassFactory` in `src/apprt/winui3/com.zig`.
- Replaced manual creation of `Grid`, `RowDefinition`, `TabView`, and `TabContentGrid` in `src/apprt/winui3_islands/tabview_runtime.zig`.
- Used `IApplicationStatics.LoadComponent` to populate `RootGrid` from `ms-appx:///TabViewRoot.xbf`.
- Used `IFrameworkElement.FindName` to retrieve `TabView` and `TabContentGrid` elements.

## XAML Requirements
The `TabViewRoot.xbf` (compiled from `TabViewRoot.xaml`) must have the following structure:
```xml
<Grid x:Class="Ghostty.TabViewRoot"
      xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      xmlns:controls="using:Microsoft.UI.Xaml.Controls">
    <Grid.RowDefinitions>
        <RowDefinition Height="40"/>
        <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <controls:TabView x:Name="TabView" Grid.Row="0" HorizontalAlignment="Stretch" VerticalAlignment="Stretch"/>
    <Grid x:Name="TabContentGrid" Grid.Row="1"/>
</Grid>
```

## Verification
The code now correctly:
1. Activates `Microsoft.UI.Xaml.Controls.Grid`.
2. Loads `TabViewRoot.xbf` into it using `LoadComponent`.
3. Finds "TabView" and "TabContentGrid" names.
4. Returns the `ITabView` pointer.
