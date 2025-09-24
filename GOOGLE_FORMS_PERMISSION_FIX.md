# Google Forms 編集権限の修正手順

## 📝 概要
Google Formsの編集権限が正しく付与されない問題を修正しました。以下の手順に従って設定を更新してください。

## ⚡ 必要な作業（所要時間：約5分）

### 1. Google Apps Scriptの再デプロイ（約3分）

#### ステップ 1: Google Apps Scriptエディタを開く
1. [Google Apps Script](https://script.google.com) にアクセス
2. 既存のプロジェクト「Forms API Web App」を開く
   - もし見つからない場合は新規作成

#### ステップ 2: 最新のコードをコピー
1. このリポジトリの `/google_apps_script/forms_api_with_sharing.gs` を開く
2. 全文をコピー
3. Google Apps Scriptエディタに貼り付け

#### ステップ 3: Web Appとしてデプロイ
1. エディタ右上の「デプロイ」→「新しいデプロイ」をクリック
2. 以下の設定で デプロイ：
   - 種類: **ウェブアプリ**
   - 説明: `Google Forms API v2 (with sharing fix)`
   - 次のユーザーとして実行: **自分**
   - アクセス可能なユーザー: **全員**
3. 「デプロイ」をクリック
4. **表示されるWeb App URLをコピー**（重要！）

### 2. Firebase Functions環境変数の設定（約1分）

#### 方法A: Firebase CLIを使用（推奨）
```bash
# プロジェクトディレクトリで実行
firebase functions:config:set google.apps_script_url="コピーしたWeb App URL"
firebase deploy --only functions
```

#### 方法B: 環境変数ファイルを直接編集
1. `functions/.env` ファイルを作成または編集
2. 以下を追加：
```
GOOGLE_APPS_SCRIPT_URL=コピーしたWeb App URL
```
3. Firebase Functionsを再デプロイ：
```bash
cd functions
npm run deploy
```

### 3. アプリでGoogleアカウントを再設定（約30秒）

1. アプリの「設定」画面を開く
2. 「Googleアカウント連携」セクションで「アカウントを変更」をタップ
3. Google Formsで使用したいアカウントを選択
4. 権限の許可画面が出たら「許可」をタップ

## ✅ 動作確認

1. 実験作成画面で「Googleフォームを作成」を選択
2. テンプレートを選んで「作成」をタップ
3. Google Formsが開いて編集できることを確認

## 🔧 トラブルシューティング

### 問題: まだ編集権限がない
**解決策:**
- Google Apps Scriptのログを確認
- Firebaseの環境変数が正しく設定されているか確認：
  ```bash
  firebase functions:config:get
  ```

### 問題: 「このアプリはGoogleで確認されていません」警告
**解決策:**
1. 開発中は「詳細」→「安全でないページに移動」を選択
2. または、Google Cloud ConsoleでテストユーザーとしてGoogleアカウントを登録

### 問題: フォームが作成されない
**解決策:**
- Firebase Functionsのログを確認：
  ```bash
  firebase functions:log
  ```

## 📚 技術的な改善内容

### Google Apps Script側の改善
- フォーム作成時に「リンクを知っている全員が編集可能」に設定
- ユーザーのメールアドレスで編集者追加を3回リトライ
- login_hintパラメータ付きの編集URLを生成

### Firebase Functions側の改善
- 複数のソースからユーザーメールを取得（優先順位付き）
- GoogleメールアドレスをFirestoreに保存して再利用
- 詳細なログ出力とエラーハンドリング

### Flutter側の改善
- GoogleアカウントのメールをFirestoreに保存
- 編集URLを優先的に使用
- 権限状態の詳細なログ記録

## 🆘 サポート

問題が解決しない場合は、以下の情報と共にissueを作成してください：
- エラーメッセージのスクリーンショット
- Firebase Functionsのログ
- 使用しているGoogleアカウントのドメイン（@gmail.comなど）