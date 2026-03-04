# macOS -> Zig/WinUI Test Parity Report

Generated: 2026-03-04 11:06:28 +09:00

## Summary

- macOS tests discovered: 60
- GTK zig tests discovered: 17
- WinUI3 zig tests discovered: 31
- Matching heuristic: token-overlap (Jaccard), not semantic execution parity
- Thresholds: strong >= 0.5, weak >= 0.2 and < 0.5

### macOS -> GTK
- strong: 0
- weak: 3
- none: 57

### macOS -> WinUI3
- strong: 0
- weak: 4
- none: 56

## Highest-Risk Gaps (lowest overlap first)

| macOS test id | best GTK score | best GTK | best WinUI3 score | best WinUI3 |
|---|---:|---|---:|---|
| GhosttyThemeTests::testIssue8282 | 0 |  | 0 |  |
| GhosttyThemeTests::testLightNativeWindowThemeWithDarkTerminal | 0 |  | 0 |  |
| GhosttyThemeTests::testLightTransparentWindowThemeWithDarkTerminal | 0 |  | 0 |  |
| GhosttyThemeTests::testQuickTerminalThemeChange | 0 |  | 0 |  |
| GhosttyThemeTests::testReloadFromDefaultThemeToDarkWindowTheme | 0 |  | 0 |  |
| GhosttyThemeTests::testReloadFromLightWindowThemeToDefaultTheme | 0 |  | 0 |  |
| GhosttyThemeTests::testReloadingFromDarkThemeToSystemLightTheme | 0 |  | 0 |  |
| GhosttyThemeTests::testReloadingLightTransparentWindowTheme | 0 |  | 0 |  |
| GhosttyThemeTests::testSwitchingSystemTheme | 0 |  | 0 |  |
| GhosttyTitlebarTabsUITests::testCustomTitlebar | 0 |  | 0 |  |
| GhosttyTitlebarTabsUITests::testTabsGeometryAfterMergingAllWindows | 0 |  | 0 |  |
| GhosttyTitlebarTabsUITests::testTabsGeometryAfterMovingTabs | 0 |  | 0 |  |
| GhosttyTitlebarTabsUITests::testTabsGeometryInFullscreen | 0 |  | 0 |  |
| GhosttyTitlebarTabsUITests::testTabsGeometryInNormalWindow | 0 |  | 0 |  |
| NSScreenTests::testLargeCoordinates | 0 |  | 0 |  |
| NSScreenTests::testOffsetScreen | 0 |  | 0 |  |
| NSScreenTests::testZeroCoordinates | 0 |  | 0 |  |
| ReleaseNotesTests::testFullGitHash | 0 |  | 0 |  |
| ReleaseNotesTests::testTaggedRelease | 0 |  | 0 |  |
| ReleaseNotesTests::testTipReleaseComparison | 0 |  | 0 |  |
| ReleaseNotesTests::testTipReleaseWithoutCurrentCommit | 0 |  | 0 |  |
| UpdateStateTests::testCheckingEquality | 0 |  | 0 |  |
| UpdateStateTests::testDownloadingEqualityWithNilExpectedLength | 0 |  | 0 |  |
| UpdateStateTests::testDownloadingEqualityWithSameProgress | 0 |  | 0 |  |
| UpdateStateTests::testDownloadingInequalityWithDifferentExpectedLength | 0 |  | 0 |  |
| UpdateStateTests::testDownloadingInequalityWithDifferentProgress | 0 |  | 0 |  |
| UpdateStateTests::testErrorEqualityWithSameDescription | 0 |  | 0 |  |
| UpdateStateTests::testErrorInequalityWithDifferentDescription | 0 |  | 0 |  |
| UpdateStateTests::testExtractingEqualityWithSameProgress | 0 |  | 0 |  |
| UpdateStateTests::testExtractingInequalityWithDifferentProgress | 0 |  | 0 |  |
| UpdateStateTests::testIdleEquality | 0 |  | 0 |  |
| UpdateStateTests::testInstallingEquality | 0 |  | 0 |  |
| UpdateStateTests::testIsIdleFalse | 0 |  | 0 |  |
| UpdateStateTests::testIsIdleTrue | 0 |  | 0 |  |
| UpdateStateTests::testPermissionRequestEquality | 0 |  | 0 |  |
| UpdateViewModelTests::testCheckingText | 0 |  | 0 |  |
| UpdateViewModelTests::testDownloadingTextWithKnownLength | 0 |  | 0 |  |
| UpdateViewModelTests::testDownloadingTextWithUnknownLength | 0 |  | 0 |  |
| UpdateViewModelTests::testDownloadingTextWithZeroExpectedLength | 0 |  | 0 |  |
| UpdateViewModelTests::testErrorText | 0 |  | 0 |  |

## Artifacts

- macOS ID ledger: docs/test-parity/macos_test_ids.csv
- Zig test ledger: docs/test-parity/zig_backend_test_ids.csv
- Raw parity matrix: docs/test-parity/macos_to_zig_parity.csv

## Notes

- This report detects likely correspondence by names/tokens only.
- Use this as triage input; then build explicit golden IDs mapping for high-confidence parity audits.
