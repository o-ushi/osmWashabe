# App Store Privacy Checklist

## Guideline 5.1.1(i) / 5.1.2(i)

- [x] OS音声認識前に日本語・英語・ベトナム語で明示同意
- [x] Apple / Android端末の認識事業者への提供とクラウド処理可能性を表示
- [x] 同意文を版付き保存（version 1）
- [x] 設定から撤回可能。拒否・撤回時は採点、録音、認識を停止
- [x] サービス層でも同意を再確認し、UI迂回時の録音を防止
- [x] `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` を3言語で具体化

## 診断ログ

- [x] 自動送信なし
- [x] メールとGoogle Apps Script webhookを別操作として選択
- [x] 含まれ得る例外、stack trace、OS、セッション、音声認識診断を明示
- [x] 送信先を各送信前に表示し、都度同意
- [x] メール失敗時にWebhookへフォールバックしない

## Google AI / 保存と削除

- [x] 固定プロンプトをGoogleへ送る通信をPrivacy画面とポリシーに記載
- [x] 設定とヘルプの両方からPrivacy画面へ到達可能
- [x] 録音、ログ、設定、お題、保持期間、削除方法を記載
- [x] Apple / Googleポリシーへのリンク
- [x] 全データ削除で録音、Dart/nativeログ、音声ログ、設定、お題、同意を削除
- [x] Voskモデルを再生成可能キャッシュとして記載し、全削除時に削除

## iOS / リリース前

- [x] Release不要のBonjour / Local Network用途説明をInfo.plistから除外
- [x] iPhone専用（`TARGETED_DEVICE_FAMILY = 1`）
- [x] 縦向きのみ
- [x] build番号を1増加
- [ ] App Store ConnectのPrivacy Policy URLを公開URLへ設定
- [ ] App Privacy回答を実装と一致させる
- [ ] 実機で初回同意、拒否、撤回、再同意、各ログ送信、全削除を確認
- [ ] Google Apps Scriptの受信・アクセス制御・保存期間を運用確認
