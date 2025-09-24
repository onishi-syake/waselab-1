# Google Forms API 修正手順

## 問題の原因
現在のGoogle Apps Script (GAS) で `FormApp.create()` がサポートされていないエラーが発生しています。
これはGoogle Workspaceの制限によるものです。

## 解決方法

### オプション1: 別のGoogleアカウントでデプロイ（推奨）

1. **別のGoogleアカウントにログイン**
   - yudai71015@gmail.com でログインしてみてください
   - このアカウントはGoogle Workspace制限を受けていない可能性があります

2. **Google Apps Scriptを新規作成**
   ```
   https://script.google.com
   ```

3. **`forms_api_final.gs`のコードをコピー**
   - `/google_apps_script/forms_api_final.gs` の内容をすべてコピー
   - 新しいGASプロジェクトに貼り付け

4. **デプロイ**
   - デプロイ → 新しいデプロイ
   - ウェブアプリとして設定
   - アクセス: 全員

5. **新しいURLで更新**
   ```bash
   firebase functions:config:set gas.url="新しいURL"
   cd functions && npm run deploy
   ```

### オプション2: テンプレートコピー方式を使用

FormApp.create()が使えない場合の代替方法です。

1. **テンプレートフォームを作成**
   - Google Formsで空のフォームを手動作成
   - フォームのURLからIDを取得
   - 例: `https://docs.google.com/forms/d/[ここがID]/edit`

2. **`forms_api_copy_template.gs`を使用**
   - TEMPLATE_FORM_IDに上記のIDを設定
   - Google Apps Scriptにデプロイ

3. **動作の仕組み**
   - テンプレートフォームをコピーして新しいフォームを作成
   - コピー後に権限設定を適用

### オプション3: 管理者に依頼

Google Workspace管理者に以下を依頼:
- yudai61104@gmail.com アカウントでFormApp.create()の制限を解除
- またはGoogle Apps Script APIの制限を緩和

## 現在の状況

- ✅ Firebase Functions更新完了（新しいGAS URL設定済み）
- ❌ GASで`FormApp.create()`がサポートされていない
- 📝 代替案を用意済み

## 推奨アクション

1. まず**オプション1**を試してください（別アカウントでデプロイ）
2. それでもダメなら**オプション2**（テンプレートコピー方式）
3. 最終手段として**オプション3**（管理者依頼）

## テスト方法

新しいGASをデプロイ後:

```bash
# test_gas_deployment.jsのURLを新しいものに更新
node test_gas_deployment.js
```

成功時の表示:
```
Editor Added: true  ← これが重要
Sharing Mode: anyone_with_link_can_edit  ← これも重要
```