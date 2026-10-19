> v2.7.5：アプリ内の導入ガイドに現在のパスで実行できるコマンドがあります。ホストへの導入・許可・実送信は利用者が確認してください。

# Squat local review plugin

確認版アプリ用の任意の連携試験パッケージです。同梱hookと通常版0.9.0は接続先が異なるため、通常版の送信連携は完了しません。通常利用には時間方式を使ってください。通常版への自動導入はしません。

- パッケージ：marketplace/plugins/squat-link-review
- 配布元：squat-review-v27
- ID：squat-link-review@squat-review-v27
- UserPromptSubmitのcommandを1件、async=true、timeout=1秒。
- 実行する小さなSwiftプログラムは、このMacの確認版受信口へ必要な情報だけを送ります。本文の保存・転送・外部AI呼び出し・会話への追加文章はありません。
- ソース：SquatBridge.swift。確認版の受信部：Sources/SquatForMac/SquatLocalLink.swift（このpluginフォルダの親が実装ルート）。

導入はCodexの公式の配布元追加→プラグイン導入→有効化→フック定義の信頼確認→テスト送信の順です。ファイルをコピーしただけで導入・許可済みとは扱いません。

導入前に実行ファイル・定義を確認してください。自分のCodex CLIでplugin marketplace addにこのmarketplaceフォルダの絶対パスを指定し、plugin addに上のIDを指定します。フックの許可はホストの確認画面で本人が行います。別の設定を上書きしたり、信頼確認を迂回したりしません。

有効な作業フォルダを持つチャットで試験してください。フォルダを移動・削除した場合は、実在する場所でチャットを開き直してください。アプリ名やsourceフィールドの固定値だけで、通常Chat/Work/Codexを自動判別できたとは扱いません。

解除はホストのプラグイン管理からこのIDと配布元だけを削除し、Squat確認版でも連携を無効化します。通常ChatGPT・Claudeの送信や回答完了には対応していません。
