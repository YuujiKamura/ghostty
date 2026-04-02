# Surface Runtime Refactoring: LoadComponent Investigation

Replacement of `XamlReader.Load` in `Surface.zig` with `LoadComponent` is proposed to match the `TabViewRoot.xbf` pattern.

## Proposed Strategy
Extract the grid creation in `Surface.zig`'s `init` method to a separate function or refactor it in-place to use `LoadComponent`.

### XAML Content (SurfaceRoot.xaml)
```xml
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="17"/>
    </Grid.ColumnDefinitions>
    <ScrollBar x:Name="ScrollBar"
               Grid.Column="1" Orientation="Vertical"
               Width="17" MinWidth="17" MaxWidth="17"
               HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
               IndicatorMode="MouseIndicator" IsTabStop="False"
               Minimum="0" Maximum="0" Value="0"
               SmallChange="1" LargeChange="10"
               ViewportSize="10"/>
</Grid>
```

### Zig Implementation Change
1. Activate `Microsoft.UI.Xaml.Controls.Grid`.
2. Load `ms-appx:///SurfaceRoot.xbf` into it using `IApplicationStatics.LoadComponent`.
3. Use `FindName("ScrollBar")` to get the `ScrollBar`.
4. Insert the `SwapChainPanel` into the `Grid.Children` at index 0.

### Code Example
```zig
const root_grid_insp = try winrt.activateInstance(grid_class);
// Create URI for ms-appx:///SurfaceRoot.xbf
// ...
try app_statics.loadComponent(root_grid_insp, uri);

const root_fe = try root_grid_insp.queryInterface(com.IFrameworkElement);
defer root_fe.release();

const sb_name = try winrt.hstring("ScrollBar");
defer winrt.deleteHString(sb_name);
const sb_insp = try root_fe.FindName(sb_name);

// Insert panel at 0
const grid_panel = try root_grid_insp.queryInterface(com.IPanel);
defer grid_panel.release();
const grid_children = try grid_panel.Children();
try grid_children.insertAt(0, panel);
```

## Benefits
- Consistency with `tabview_runtime.zig` and compiled XAML approach.
- Removal of hardcoded XAML strings.
- Improved separation of UI and logic.
