/**
 * osmWashabe クラッシュログ受信（Google Apps Script）
 *
 * 使い方:
 * 1. script.google.com でプロジェクト「osmWashabe」を開く
 * 2. このファイルの中身をすべて コード.gs に貼り付けて保存
 * 3. デプロイ → 新しいデプロイ → 種類: ウェブアプリ
 *    - 次のユーザーとして実行: 自分
 *    - アクセスできるユーザー: 全員
 * 4. 表示された URL を lib/services/crash_log_service.dart の _webhookUrl に貼る
 */

var LOG_RECIPIENT = 'osam.in.az@gmail.com';

/** ブラウザで URL を開いて「OK」と出ればデプロイ成功 */
function doGet() {
  return ContentService.createTextOutput('osmWashabe crash log receiver OK');
}

function doPost(e) {
  var data = JSON.parse(e.postData.contents);
  var subject = data.subject || 'osmWashabe クラッシュログ';
  var body = data.body || '(ログなし)';

  MailApp.sendEmail(LOG_RECIPIENT, subject, body);

  return ContentService
    .createTextOutput(JSON.stringify({ result: 'ok' }))
    .setMimeType(ContentService.MimeType.JSON);
}
