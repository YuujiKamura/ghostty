# Debug doCompositionUpdate in Ghostty TSF

src/apprt/winui3_islands/tsf.zig の doCompositionUpdate() が呼ばれるが、中のテキスト抽出が動いていない。

ログでは `TSF: doCompositionUpdate ec=...` は出るが、その後のログ（finalized text, active composition等）が一切出ない。

doCompositionUpdate内の各ステップにログを追加して、どこで早期returnしているか特定しろ。

具体的には以下の各ステップの直後にApp.fileLog()を追加:
1. GetStart → fullRangeのhrをログ
2. ShiftEnd → fullRangeLengthをログ
3. TrackProperties → propsのhrをログ  
4. EnumRanges → enumRangesのhrをログ
5. IEnumTfRanges.Next → rangesCount, hr をログ
6. GetValue → hr, composing判定をログ
7. GetText → text_len, テキスト内容をログ
8. GetSelection → cursorPosをログ
9. finalized/active テキストの長さをログ
10. handleOutput/handlePreedit コールバック呼び出し前にログ

ファイル: src/apprt/winui3_islands/tsf.zig
関数: doCompositionUpdate (grep "fn doCompositionUpdate" で見つかる)

変更後ビルド: zig build -Dapp-runtime=winui3_islands -Dslow-safety=false --prefix zig-out-winui3-islands

既存のtsf.zigを読んでから変更を入れろ。
