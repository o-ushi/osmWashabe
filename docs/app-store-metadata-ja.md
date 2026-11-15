# osmWAshabe App Store Connect 申請用文案（ベトナム語・v3.2.3）

最終更新：2026年11月15日

App Store Connect の各フィールドにそのまま貼り付けて使えます。文字数は提出前に再確認してください。
ストアの各欄（サブタイトル・プロモーション・概要・キーワード・最新情報）はベトナム語、審査員へのメモは日本語です。

---

## サブタイトル（30文字以内）

アプリ名の下に表示され、検索の対象にもなります。

```
Bốc đề, nói tiếng Nhật kịp giờ
```

（30文字）

---

## プロモーションテキスト（170文字以内）

審査通過後も、新バージョンを出さずに更新できます。

```
Bốc đề và nói tiếng Nhật đến khi hết giờ. Từ 15 giây chuẩn bị, 60 giây nói, đến thi thử 10 câu liên tiếp. Chấm điểm để biết cần cải thiện ở đâu.
```

（144文字）

---

## 概要（説明・4,000文字以内）

```
osmWAshabe là ứng dụng luyện khả năng nói tiếng Nhật. Bốc đề, giới hạn thời gian và cứ thế nói thành lời. Lặp lại nhiều lần, bạn sẽ dần có khả năng sắp xếp ý ngay tại chỗ.

■ Luyện từng câu
・Chọn số giây rồi “Bốc đề”. ▶ để bắt đầu, ⏸ để tạm dừng, ↺ để làm lại
・Với “15＋60 giây”, bạn chuẩn bị 15 giây rồi nói 60 giây
・Có thể nghe đọc to đề bài bằng nút loa

■ Thi thử
・Làm 10 câu liên tiếp. Hết giờ sẽ chuyển sang đề tiếp theo

■ Chấm điểm (tùy chọn)
・Khi bật chấm điểm, kết quả sẽ mở ra sau khi bạn nói xong
・Có giải thích theo từng chỉ số, giúp biết cần cải thiện ở đâu
・Xem lại kết quả chấm lần trước và lịch sử chấm điểm

■ Thêm đề bài
・Nhờ AI của Google tạo đề bài, rồi sao chép câu trả lời để nhập vào
・Cách nhập cũng được hướng dẫn ở màn hình hướng dẫn sử dụng

■ Giọng đọc tự nhiên hơn
・Tải giọng tiếng Nhật chất lượng cao (như Kyoko, Otoya) trong Cài đặt của iPhone để nghe đọc dễ hơn

■ Hỗ trợ 3 ngôn ngữ
日本語・English・Tiếng Việt

■ Quyền riêng tư
・Không cần đăng ký tài khoản. Không quảng cáo, không phân tích truy cập, không theo dõi
・Cài đặt, đề bài và kết quả chấm điểm được lưu trên máy, không gửi về máy chủ của nhà phát triển
・Trước lần chấm điểm đầu tiên, ứng dụng hỏi sự đồng ý rồi mới chuyển bản ghi âm thành văn bản bằng nhận dạng giọng nói của máy. Có thể rút lại đồng ý bất cứ lúc nào trong Cài đặt
・Khi tạo đề bài, chỉ gửi đến Google câu yêu cầu cố định do ứng dụng chuẩn bị. Không gửi bản ghi âm hay cài đặt
・Nhật ký lỗi (crash log) không được gửi tự động. Mỗi lần gửi, bạn xác nhận nội dung và nơi nhận trước

■ Thiết bị hỗ trợ
・iPhone・iPad (màn hình dọc)

Càng nói ra nhiều, lời nói càng đến dễ dàng. Hôm nay cũng thử nói một câu nhé.
```

（1623文字）

---

## キーワード（100文字以内）

カンマ区切り。カンマの後ろにスペースは入れない（文字数節約のため）。アプリ名に含まれる語は入れない。

```
tiếng Nhật,luyện nói,hội thoại,thi thử,phỏng vấn,hẹn giờ,chấm điểm,du học,việc làm,diễn thuyết
```

（94文字）

---

## このバージョンの最新情報（v3.2.3）

```
・Sắp xếp lại phần tạo âm thanh (âm báo hẹn giờ, âm thanh giữ hoạt động nền) để hoạt động ổn định hơn
```

（100文字）

---

## 審査員へのメモ（App Review Information > Notes）

```
2026/11/15
いつもアプリを審査頂きましてありがとうございます。
先に公開したVersion 3.2.2に対して、下記修正を行なっています。
・タイマーの合図の音と、バックグラウンド保持用の無音の音声データを作る内部処理を共通化（出力される音声は従来と同一です）
新たな権限の要求、データの収集・送信先の変更はございません。
先に一度承認をいただいた内容から、上記修正以外の機能変更やビジネスモデルの変更はございません。
お手数をおかけして恐縮ですが、ご確認のほどよろしくお願いいたします。
```

---

## 提出前チェックリスト

- [ ] App Store Connect で新しいバージョンを 3.2.3 で作成し、`pubspec.yaml` のバージョン（3.2.3+1）と一致している（公開済みの 3.2.2 より大きいこと）
- [ ] App Privacy の回答は前バージョンから変更なし
- [ ] 実機で試した（タイマーの合図の音／アプリを裏に回したときの保持／採点のオン・オフと結果）
