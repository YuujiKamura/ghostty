# WinUI3 IME Character Deduplication Requirements

## User story

As a terminal user, I want symbols and other Unicode characters typed or pasted immediately after Japanese IME input to reach the terminal, so recent IME commits do not eat unrelated text.

## Requirements

1. The input path may suppress a `CharacterReceived` unit as a duplicate only when it matches a UTF-16 unit from the immediately preceding TSF commit and arrives within the existing freshness window.
2. A fresh but different Unicode unit must be delivered normally.
3. Existing TSF duplicate suppression and stale-commit behavior must remain covered by pure logic tests.
4. The WinUI3 build, strict runtime artifact check used by CI, and applicable input smoke tests must pass.
