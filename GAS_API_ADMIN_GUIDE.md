# Google Apps Script API 制限緩和ガイド（管理者向け）

## 管理コンソールでの設定手順

### 1. Google Admin Consoleにアクセス
```
https://admin.google.com
```
管理者アカウント（おそらくyudai61104@gmail.com）でログイン

### 2. Apps Script APIの設定

#### 方法A: アプリケーションアクセス制御

1. **メニューナビゲーション**
   - 「アプリ」→「Google Workspace」→「Google Apps Script」
   - または「セキュリティ」→「APIコントロール」→「アプリのアクセス制御」

2. **Google Apps Scriptの設定**
   - 「Google Apps Script」を検索
   - ステータスを確認（制限されている場合は「制限付き」と表示）
   - 「アクセスを変更」をクリック

3. **アクセスレベルを変更**
   - 「信頼できる」または「制限なし」に変更
   - 特定のユーザー/グループに適用する場合は対象を選択

#### 方法B: APIの管理

1. **APIコントロール**
   - 「セキュリティ」→「APIコントロール」
   - 「APIの管理」または「ドメイン全体のデリゲーション」

2. **Google Apps Script APIを有効化**
   - 「APIアクセスを管理」
   - Google Apps Script APIを探す
   - 「有効」にチェック

3. **高度な設定**
   - 「信頼できないアプリへのアクセス」を許可
   - 「内部アプリケーション」の制限を緩和

### 3. Drive APIとForms APIの設定

FormApp.create()を使用するには、以下のAPIも有効化が必要：

1. **Google Drive API**
   - 「アプリ」→「Google Workspace」→「ドライブとドキュメント」
   - 「共有設定」で以下を確認：
     - ✅ ユーザーがドライブ内のファイルを外部と共有できる
     - ✅ ユーザーがファイルの所有権を譲渡できる

2. **Google Forms設定**
   - 「アプリ」→「Google Workspace」→「Google Forms」
   - アクセスを「オン」に設定
   - 「フォームの作成を許可」を有効化

### 4. スクリプトランタイムの設定

1. **開発者向け設定**
   - 「セキュリティ」→「APIコントロール」→「Apps Script設定」

2. **実行時の設定**
   - ✅ 「ユーザーがApps Scriptプロジェクトを作成できる」
   - ✅ 「外部のWebアプリケーションとして公開できる」
   - ✅ 「トリガーの作成を許可」
   - ✅ 「外部APIへのアクセスを許可」

### 5. OAuth スコープの設定

1. **OAuth同意画面**
   - 「セキュリティ」→「APIコントロール」→「OAuth同意画面」

2. **スコープの設定**
   必要なスコープを追加：
   ```
   https://www.googleapis.com/auth/forms
   https://www.googleapis.com/auth/drive
   https://www.googleapis.com/auth/script.external_request
   ```

## トラブルシューティング

### エラー: 「この操作はサポートされていません」

**原因と対処法：**

1. **組織ポリシー**
   - 「セキュリティ」→「セキュリティルール」
   - 「データ保護」ルールを確認
   - FormApp.create()をブロックするルールがないか確認

2. **ユーザー単位の制限**
   - 「ユーザー」→ 対象ユーザー（yudai61104@gmail.com）
   - 「アプリとサービス」→「追加のサービス」
   - Google Apps Scriptへのアクセスを確認

3. **ドメイン全体の設定**
   - 「アカウント設定」→「ドメイン」
   - 「新しいサービスのデフォルト設定」を「オン」に

### 即効性のある対処法

もし上記の設定が複雑な場合：

1. **個人Googleアカウントを使用**
   - yudai71015@gmail.com（個人アカウント）でGASをデプロイ
   - 個人アカウントは通常制限が少ない

2. **サービスアカウントの作成**
   - Google Cloud Consoleでサービスアカウントを作成
   - 必要な権限を付与
   - サービスアカウントでGASを実行

## 設定変更後の確認

1. **GASエディタでテスト**
   ```javascript
   function testFormCreation() {
     try {
       const form = FormApp.create('Test Form');
       console.log('Success! Form ID:', form.getId());
       // 作成したフォームを削除
       DriveApp.getFileById(form.getId()).setTrashed(true);
     } catch (e) {
       console.error('Error:', e.toString());
     }
   }
   ```

2. **権限の確認**
   - GASエディタで上記の関数を実行
   - エラーが出なければ設定成功

## 注意事項

- 設定変更は最大48時間かかる場合があります
- 一部の設定は組織全体に影響します
- セキュリティレベルを下げる場合は慎重に検討してください

## 代替案

管理コンソールでの設定が難しい場合：

1. **個人Googleアカウントでデプロイ**
   - 最も簡単で即効性がある
   - yudai71015@gmail.comを使用

2. **Google Cloud Functions使用**
   - GASの代わりにCloud Functionsを使用
   - より柔軟な権限管理が可能

3. **既存フォームのコピー方式**
   - forms_api_copy_template.gsを使用
   - FormApp.create()を使わない方法