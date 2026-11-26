# Design: WinUI3 IME Character Deduplication

The TSF output callback records the first UTF-16 code unit of the committed text alongside its timestamp. The subsequent XAML `CharacterReceived` callback consumes that pending record and suppresses only a matching unit inside the existing freshness window. A non-matching unit clears the pending record and continues through normal input handling.

This keeps deduplication state one-shot and bounded, preserves the current timestamp policy, and prevents an unrelated symbol from being classified as the TSF duplicate. Pure helper tests exercise both matching and mismatching fresh input.
