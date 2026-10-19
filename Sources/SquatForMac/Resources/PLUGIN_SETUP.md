# Squat Link — ローカルCodex用の導入ガイド

> **0.9.0の注意：以下は確認版専用の導入手順です。** 同梱hookは確認版の受信口へ接続し、通常版とは接続先が異なります。通常版でこの手順を行っても、送信連携の接続は完了しません。日常利用には「利用時間」による通知を使ってください。接続先を揃えた実機検証が終わるまで、通常版向けの手順として案内しません。

確認版では、設定 →「通知とサウンド」→「導入ガイド」で、アプリ内の案内を開けます。

1. 導入状態を確認します。公式Codex CLIの `plugin list --marketplace squat-review-v27 --json` を読み取り専用で実行します。コマンドがない・失敗・期限切れ・読み取れない形式の場合は「状態を確認できません」です。未導入とは断定しません。
2. アプリ内ガイドで同梱パッケージを確認し、「導入コマンドをコピー」から公式の配布元追加・プラグイン導入を行います。アプリ本体のResources/SquatPluginに含まれるため、元の作業フォルダは不要です。アプリを移動した場合、導入ガイドから新しいコマンドをコピーしてください。
3. ホストの管理画面で `squat-link-review@squat-review-v27` を有効化します。フックの処理内容を確認し、ホスト側で許可します。インストールだけでは許可されません。
4. ホストの案内に従い、新しいローカルCodexチャットを開きます。実在する作業フォルダを使用します。
5. Squatで「接続テストを始める」を押してから、そのCodexチャットで短い指示を送信します。受信を確認してから「AIに指示を送ったあと」を選びます。接続テストの受信待ちは約2分です。届かない場合は再開始し、有効化・許可・新しいチャットを確認してください。

## 状態の意味

- 未導入：導入一覧の取得に成功し、対象IDがなかった。
- 導入済み・無効：対象プラグインが導入されているが無効。
- 導入済み・有効：対象が有効。これだけでフックの許可・実受信は証明しない。
- 状態を確認できません：CLI不在、失敗、タイムアウト、形式不明など。
- 接続済み：確認版が実際に送信イベントを受信した。最終受信時刻も表示する。

## 対応範囲

Codexのローカル環境の送信時イベント用です。通常ChatGPT・Claudeの送信、および回答完了の検知は含みません。時間による通知はプラグイン不要です。送信連携が失敗しても、時間モードへ勝手に切り替えません。

## 情報と解除

ホストからフックに入力が渡ります。同梱の非同期ヘルパーは会話本文を保存・転送せず、識別子と時刻など必要な送信イベント情報だけを同一Mac内のSquatへ渡します。外部AI呼び出し・会話への追加出力はありません。解除はSquatの「連携を無効化」と、ホストの管理画面から対象プラグインの削除を行います。

公式説明：https://learn.chatgpt.com/docs/hooks

# English

**0.9.0 limitation: the instructions below are for the review app only. The bundled hook and regular app use different receivers, so this flow cannot connect the regular app. Use time-based reminders for daily use.**

In the review app, open Settings → Notifications & Sound → Setup guide. Inspect the bundled package, copy and run its install commands, enable the plugin and trust its hook in the host, then start a connection test and send a short message in a new local Codex chat with an existing working folder. Installation and event reception are checked separately. An unavailable inventory is reported as unknown, never absent. Ordinary ChatGPT/Claude and response completion are not supported. Time-based reminders work without this integration. Disable the connection in Squat and uninstall the plugin in the host to remove it.
