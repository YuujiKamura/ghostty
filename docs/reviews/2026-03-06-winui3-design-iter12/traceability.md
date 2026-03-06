# Traceability (Iteration 12)

## Scope
- Reduce local/manual COM release handling in `src/apprt/winui3/App.zig` by applying `winrt.ComRef` guards.
- Keep ownership-release sites on long-lived fields unchanged (`self.tab_view`, `self.window`, etc.).

## Touched Areas
- `createAggregatedApplication`: `IApplicationFactory` guard.
- `createWindowAndHooks`: `IInspectable` window activation + `IWindowNative` guard.
- `createInitialSurfaceContent`: guards for `ITabViewItem`, `IContentControl`, placeholder and tab-item vector.
- `validateTabViewParity`: guards for content/tab-item inspection path.
- `wrapInBorder` / `wrapInGrid`: guard `IBorder`, `IPanel`, and children vector.
- `run`: guard `IApplicationStatics`.
- `onTabCloseRequested`: guard tab args/tab items/item inspectables.
- `attachSurfaceToTabItem`: placeholder/framework-element guard.
- `activateXamlType(provider path)`: guard `IXamlType`.
- `boxString`, `loadXamlResources`, `verifyTabItemHasContent`, `setTitle`: temporary object guards.

## Verification
- `zig build` executed and passed (`zig-build.raw.txt`, `EXIT_CODE=0`).
- AI architecture review executed via `ai-code-review`:
  - command: `cargo run --bin review -- --analyze C:\\Users\\yuuji\\ghostty-win\\src\\apprt\\winui3\\App.zig --backend gemini --prompt architecture --context`
  - raw output: `app-architecture.raw.txt` (`EXIT_CODE=0`)

## Remaining Explicit release() Sites in App.zig
- Full-cleanup ownership releases and state-transition releases intentionally left as-is:
  - app lifecycle fields (`self.tab_view`, `self.window`, `self.xaml_app`, `self.xaml_controls_resources`)
  - container toggle ownership handoff (`tvi`, `tv`)
  - surface tab-item replacement old pointer release
