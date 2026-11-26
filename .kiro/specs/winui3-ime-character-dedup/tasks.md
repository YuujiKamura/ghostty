# Tasks: WinUI3 IME Character Deduplication

- [x] Add pure regression coverage showing a different fresh Unicode character is not suppressed while the matching TSF character is.
- [x] Track the first UTF-16 unit of the latest TSF commit and match it in the XAML duplicate guard.
- [x] Pass all 17 TSF logic tests and the WinUI3 build.
- [x] Pass the strict CI runtime artifact check and all five selected WinUI3 smoke tests.
- [x] Verify that an injected TSF commit containing Japanese text and a circled number reaches the WinUI3 terminal once.
