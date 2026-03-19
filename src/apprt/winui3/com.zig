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
pub const IID_TypedEventHandler_ResourceManagerRequested = gen.IID_TypedEventHandler_ResourceManagerRequested;
pub const IID_TypedEventHandler_WindowClosed = gen.IID_TypedEventHandler_Closed;
pub const IID_KeyEventHandler = gen.KeyEventHandler.IID;
pub const IID_PointerEventHandler = gen.PointerEventHandler.IID;
pub const IID_CharacterReceivedHandler = gen.IID_TypedEventHandler_CharacterReceived;
pub const IID_ScrollEventHandler = gen.ScrollEventHandler.IID;
pub const IID_RangeBaseValueChangedEventHandler = gen.RangeBaseValueChangedEventHandler.IID;
pub const IRangeBaseValueChangedEventArgs = gen.IRangeBaseValueChangedEventArgs;
pub const IID_TappedEventHandler = gen.TappedEventHandler.IID;
pub const IID_TextChangedEventHandler = gen.TextChangedEventHandler.IID;
pub const IID_TextCompositionStartedHandler = gen.IID_TypedEventHandler_TextCompositionStarted;
pub const IID_TextCompositionChangedHandler = gen.IID_TypedEventHandler_TextCompositionChanged;
pub const IID_TextCompositionEndedHandler = gen.IID_TypedEventHandler_TextCompositionEnded;

// --- Base interfaces (from generated) ---
pub const IUnknown = gen.IUnknown;
pub const IInspectable = gen.IInspectable;

// --- Generated interfaces ---
pub const IApplicationStatics = gen.IApplicationStatics;
pub const IApplicationFactory = gen.IApplicationFactory;
pub const IApplication = gen.IApplication;
pub const IDebugSettings = gen.IDebugSettings;
pub const IDebugSettings2 = gen.IDebugSettings2;
pub const IDependencyObject = gen.IDependencyObject;
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
pub const IVisualTreeHelperStatics = gen.IVisualTreeHelperStatics;
pub const IResourceDictionary = gen.IResourceDictionary;
pub const IColumnDefinition = gen.IColumnDefinition;
pub const IRangeBase = gen.IRangeBase;
pub const IScrollBar = gen.IScrollBar;
pub const IScrollEventArgs = gen.IScrollEventArgs;
pub const IXamlReaderStatics = gen.IXamlReaderStatics;
pub const IUriRuntimeClass = gen.IUriRuntimeClass;
pub const IUriRuntimeClassFactory = gen.IUriRuntimeClassFactory;

// --- XAML Input event args (from generated) ---
pub const Point = gen.Point;
pub const IKeyRoutedEventArgs = gen.IKeyRoutedEventArgs;
pub const ICharacterReceivedRoutedEventArgs = gen.ICharacterReceivedRoutedEventArgs;
pub const ITextCompositionStartedEventArgs = gen.ITextCompositionStartedEventArgs;
pub const ITextCompositionChangedEventArgs = gen.ITextCompositionChangedEventArgs;
pub const ITextCompositionEndedEventArgs = gen.ITextCompositionEndedEventArgs;
// WinUI3 pointer interfaces use DIFFERENT IIDs and vtable layouts from UWP.
// The generated versions are from Windows.UI.Input (UWP); the hand-written
// native versions are from Microsoft.UI.Input (WinUI3) with correct slot order.
pub const IPointerRoutedEventArgs = native.IPointerRoutedEventArgs;
pub const IPointerPoint = native.IPointerPoint;
pub const IPointerPointProperties = native.IPointerPointProperties;

// --- Generated value types ---
pub const Color = gen.Color;
pub const Size = gen.Size;
pub const Rect = gen.Rect;
pub const Thickness = gen.Thickness;
pub const GridLength = gen.GridLength;
pub const GridUnitType = gen.GridUnitType;
pub const HorizontalAlignment = gen.HorizontalAlignment;
pub const VerticalAlignment = gen.VerticalAlignment;
pub const FocusState = gen.FocusState;

// --- Hand-written native interfaces (cannot be auto-generated from WinMD) ---
pub const IVector = native.IVector;
pub const IPropertyValue = native.IPropertyValue;
pub const IPropertyValueStatics = native.IPropertyValueStatics;
pub const ISwapChainPanelNative = native.ISwapChainPanelNative;
pub const IWindowNative = native.IWindowNative;
pub const ISplitButton = native.ISplitButton;
pub const IMenuFlyout = native.IMenuFlyout;
pub const IMenuFlyoutItem = native.IMenuFlyoutItem;
pub const IMenuFlyoutSeparator = native.IMenuFlyoutSeparator;

// --- XAML Islands interfaces (hand-written, IIDs from WinMD via win-zig-bindgen) ---
pub const WindowId = native.WindowId;
pub const ContentSizePolicy = native.ContentSizePolicy;
pub const IDesktopWindowXamlSource = native.IDesktopWindowXamlSource;
pub const IDesktopWindowXamlSourceFactory = native.IDesktopWindowXamlSourceFactory;
pub const IDesktopChildSiteBridge = native.IDesktopChildSiteBridge;
pub const IClosable = native.IClosable;
