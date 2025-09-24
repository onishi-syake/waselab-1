# Google Forms 権限修正ガイド

## 現在の問題
- フォームは作成されるが、yudai71015@gmail.com（連携アカウント）に編集権限が付与されない
- 「Editor added: false」「Sharing mode: unknown」と表示される
- 原因：Google Apps Scriptが正しくデプロイされていない

## 解決手順

### 1. 新しいGoogle Apps Scriptをデプロイ

1. **Google Apps Scriptを開く**
   - https://script.google.com にアクセス
   - yudai61104@gmail.com でログイン（重要：このアカウントでデプロイする必要があります）

2. **新しいプロジェクトを作成**
   - 「新規プロジェクト」をクリック
   - プロジェクト名を「Forms API Final」に変更

3. **コードを貼り付け**
   - `google_apps_script/forms_api_final.gs` の内容をすべてコピー
   - Google Apps Scriptエディタに貼り付け
   - Ctrl+S（またはCmd+S）で保存

4. **テスト実行**（重要）
   ```javascript
   // エディタ上部のプルダウンから「testDirectly」を選択
   // 「実行」ボタンをクリック
   // 初回は権限の承認が必要
   ```

5. **デプロイ**
   - 右上の「デプロイ」ボタン → 「新しいデプロイ」
   - 設定：
     - 種類：「ウェブアプリ」
     - 説明：「Forms API v4.0」
     - 実行ユーザー：「自分」（yudai61104@gmail.com）
     - アクセスできるユーザー：「全員」
   - 「デプロイ」をクリック

6. **URLをコピー**
   - デプロイ完了後、表示されるURLをコピー
   - 形式：`https://script.google.com/macros/s/[ID]/exec`

### 2. Firebase Functionsの更新

```bash
# 1. Firebase Functionsのディレクトリに移動
cd /Users/yudaimiyamoto/Desktop/プログラム/flutter/waselab/functions

# 2. 環境変数を更新（新しいURLに置き換え）
firebase functions:config:set gas.url="新しいGAS_URL"

# 3. デプロイ
npm run deploy
```

### 3. 動作確認

1. **ローカルテスト**
   ```bash
   # test_gas_deployment.js のURLを更新して実行
   node test_gas_deployment.js
   ```

2. **アプリでテスト**
   - アプリを開く
   - 設定 → Googleアカウント連携 → yudai71015@gmail.com を確認
   - 実験作成 → Google Formsで作成
   - 作成されたフォームが自動的に開く

## 期待される結果

正しくデプロイされた場合、ログに以下が表示されます：

```json
{
  "success": true,
  "formId": "1abc...",
  "editorAdded": true,  // ← これがtrueになる
  "sharingMode": "anyone_with_link_can_edit",  // ← unknownではなくなる
  "editorsAdded": ["yudai71015@gmail.com"],
  "message": "フォームが作成されました（リンクを知っている全員が編集可能）"
}
```

## トラブルシューティング

### 「この操作はサポートされていません」エラー
- 原因：FormApp.create()が制限されている
- 解決策：
  1. Google Workspaceの管理コンソールで制限を確認
  2. または別のGoogleアカウントでデプロイ

### 権限が付与されない
- 原因：DriveApp.addEditor()の制限
- 解決策：
  1. リンク共有（anyone_with_link_can_edit）を有効化
  2. これにより誰でも編集可能になる

### レスポンスが不完全
- 原因：Google Apps Scriptのコードエラー
- 解決策：forms_api_final.gsを使用（エラーハンドリング強化版）

## 重要な注意点

1. **デプロイアカウント**
   - yudai61104@gmail.com でデプロイする必要がある
   - このアカウントがフォームの所有者になる

2. **権限の流れ**
   - Firebase Auth: yudai5287@ruri.waseda.jp
   - 連携Google: yudai71015@gmail.com（編集権限を付与したい）
   - GAS実行: yudai61104@gmail.com（フォーム所有者）

3. **セキュリティ**
   - リンク共有を有効にすると、URLを知っている人は誰でも編集可能
   - より厳密な制御が必要な場合は、特定ユーザーのみに権限付与

## 確認方法

デプロイ後、以下を確認：

1. GASのGETリクエストテスト：
   ```bash
   curl "新しいGAS_URL"
   ```
   → バージョン4.0が返ってくることを確認

2. フォーム作成テスト：
   - アプリから実験を作成
   - ログで`editorAdded: true`を確認
   - フォームが自動的に開き、編集可能なことを確認

## サポート

問題が解決しない場合：
1. Google Apps Scriptの実行ログを確認
2. Firebase Functionsのログを確認
3. このガイドの手順を再度確認