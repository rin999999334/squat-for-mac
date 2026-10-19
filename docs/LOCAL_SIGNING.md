# Local signing / ローカルビルドの署名

`./scripts/build.sh` は、署名を指定しない場合にローカル用のアドホック署名を使います。完成先は `dist/Squat for Mac.app` です。Developer ID署名・Appleの公証とは異なり、ダウンロードした別Macでの起動を保証しません。

コードの更新によりカメラ権限を再度求められる場合があります。すでに利用可能な署名用証明書がある開発者は、`security find-identity -v -p codesigning` で確認した40桁の証明書SHA-1を `SQUAT_SIGN_IDENTITY` に指定できます。`scripts/select-signing-identity.sh` でこのプロジェクト向けに保存することもできます。

```sh
SQUAT_SIGN_IDENTITY="YOUR_40_CHARACTER_SHA1" ./scripts/build.sh
```

上記の値は説明用です。存在しない署名IDを指定した場合は停止し、アドホック署名へ自動で戻しません。署名証明書の秘密鍵をリポジトリや配布ZIPへ入れないでください。署名方法・bundle ID・設置先が変わると再許可が必要になる場合があり、同じ署名でも権限の維持は実機で確認します。

現時点の一般配布は準備中です。GatekeeperやSystem Integrity Protectionの無効化、カメラ権限データベースの書き換えは行いません。

[Appleの署名・公証の説明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [配布計画](RELEASE_PLAN.md)
