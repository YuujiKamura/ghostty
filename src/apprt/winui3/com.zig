//! WinUI 3 COM interface facade.
//! Combines generated definitions with hand-written native interfaces.

const gen = @import("com_generated.zig");
const native = @import("com_native.zig");

// --- Helpers & common types (from generated) ---
pub const VtblPlaceholder = gen.VtblPlaceholder;
pub const comRelease = gen.comRelease;
pub const comQueryInterface = gen.comQueryInterface;
pub const hrCheck = gen.hrCheck;
pub const isValidComPtr = gen.isValidComPtr;

// --- IID constants ---
pub const IID_RoutedEventHandler = gen.IID_RoutedEventHandler;
pub const IID_SizeChangedEventHandler = gen.IID_SizeChangedEventHandler;
pub const IID_TypedEventHandler_TabCloseRequested = gen.IID_TypedEventHandler_TabCloseRequested;
pub const IID_TypedEventHandler_AddTabButtonClick = gen.IID_TypedEventHandler_AddTabButtonClick;
pub const IID_SelectionChangedEventHandler = gen.IID_SelectionChangedEventHandler;
pub const IID_TypedEventHandler_WindowClosed = gen.IID_TypedEventHandler_WindowClosed;
pub const IID_KeyEventHandler = gen.KeyEventHandler.IID;
pub const IID_PointerEventHandler = gen.PointerEventHandler.IID;
pub const IID_CharacterReceivedHandler = native.IID_CharacterReceivedHandler;
pub const IID_ScrollEventHandler = gen.ScrollEventHandler.IID;

// --- Base interfaces (from generated) ---
pub const IUnknown = gen.IUnknown;
pub const IInspectable = gen.IInspectable;

// --- Generated interfaces ---
pub const IApplicationStatics = gen.IApplicationStatics;
pub const IApplicationFactory = gen.IApplicationFactory;
pub const IApplication = gen.IApplication;
pub const IWindow = gen.IWindow;
pub const ITabView = gen.ITabView;
pub const ITabViewItem = gen.ITabViewItem;
pub const ITabViewTabCloseRequestedEventArgs = gen.ITabViewTabCloseRequestedEventArgs;
pub const IContentControl = gen.IContentControl;
pub const IUIElement = gen.IUIElement;
pub const IFrameworkElement = gen.IFrameworkElement;
pub const IXamlMetadataProvider = gen.IXamlMetadataProvider;
pub const IXamlType = gen.IXamlType;
pub const ITextBox = gen.ITextBox;
pub const ISolidColorBrush = gen.ISolidColorBrush;
pub const IControl = gen.IControl;
pub const IPanel = gen.IPanel;
pub const IGrid = gen.IGrid;
pub const IGridStatics = gen.IGridStatics;
pub const IRowDefinition = gen.IRowDefinition;
pub const IResourceDictionary = gen.IResourceDictionary;
pub const IColumnDefinition = gen.IColumnDefinition;
pub const IRangeBase = gen.IRangeBase;
pub const IScrollBar = gen.IScrollBar;
pub const IScrollEventArgs = gen.IScrollEventArgs;
pub const IXamlReaderStatics = gen.IXamlReaderStatics;

// --- XAML Input event args (from generated) ---
pub const Point = gen.Point;
pub const IKeyRoutedEventArgs = gen.IKeyRoutedEventArgs;
pub const ICharacterReceivedRoutedEventArgs = gen.ICharacterReceivedRoutedEventArgs;
pub const IPointerRoutedEventArgs = gen.IPointerRoutedEventArgs;
pub const IPointerPoint = gen.IPointerPoint;
pub const IPointerPointProperties = gen.IPointerPointProperties;

// --- Generated value types ---
pub const Color = gen.Color;
pub const Size = gen.Size;
pub const Rect = gen.Rect;
pub const Thickness = gen.Thickness;
pub const GridLength = gen.GridLength;
pub const GridUnitType = gen.GridUnitType;
pub const HorizontalAlignment = gen.HorizontalAlignment;
pub const VerticalAlignment = gen.VerticalAlignment;

// --- Hand-written native interfaces (cannot be auto-generated from WinMD) ---
pub const IApplicationAbi = native.IApplicationAbi;
pub const IVector = native.IVector;
pub const IPropertyValue = native.IPropertyValue;
pub const IPropertyValueStatics = native.IPropertyValueStatics;
pub const ISwapChainPanelNative = native.ISwapChainPanelNative;
pub const IWindowNative = native.IWindowNative;
