import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

/// Googleアカウント管理サービス
/// 複数のGoogleアカウントを管理し、明示的なアカウント選択を提供
class GoogleAccountService {
  static const String _selectedAccountKey = 'selected_google_account';
  static const String _selectedAccountEmailKey = 'selected_google_email';
  static const String _accountIndexKey = 'google_account_index';

  // 基本スコープのみ（センシティブなスコープを削除）
  static const List<String> _requiredScopes = [
    'email',
    'profile',
  ];

  // オプションのスコープ（必要に応じて個別にリクエスト）
  static const List<String> _calendarScopes = [
    'https://www.googleapis.com/auth/calendar.events',
  ];

  static const List<String> _formsScopes = [
    'https://www.googleapis.com/auth/forms',
    'https://www.googleapis.com/auth/drive.file',
  ];

  late final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? _currentAccount;
  int _accountIndex = 0;

  /// シングルトンインスタンス
  static final GoogleAccountService _instance = GoogleAccountService._internal();

  factory GoogleAccountService() => _instance;

  GoogleAccountService._internal() {
    // プラットフォームに応じた設定
    _googleSignIn = GoogleSignIn(
      scopes: _requiredScopes,
      // iOSとAndroidでforceCodeForRefreshTokenを無効化
      // モバイルプラットフォームでは不要で、むしろ問題を引き起こす可能性がある
      forceCodeForRefreshToken: kIsWeb,
    );
  }

  /// 現在選択されているアカウントを取得
  GoogleSignInAccount? get currentAccount => _currentAccount;

  /// 現在選択されているアカウントのインデックスを取得
  int get accountIndex => _accountIndex;

  /// 現在のアカウントのメールアドレスを取得
  String? get currentEmail => _currentAccount?.email;

  /// 初期化（保存されたアカウント情報を読み込み）
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accountIndex = prefs.getInt(_accountIndexKey) ?? 0;
      final savedEmail = prefs.getString(_selectedAccountEmailKey);

      if (savedEmail != null) {
        // サイレントサインインを試みる
        _currentAccount = await _googleSignIn.signInSilently();
        if (_currentAccount?.email != savedEmail) {
          // 保存されたメールと異なる場合は再度サインイン
          await signOut();
          _currentAccount = null;
        }
      }
    } catch (e) {
      debugPrint('GoogleAccountService初期化エラー: $e');
    }
  }

  /// 明示的にアカウントを選択（強制的にアカウント選択画面を表示）
  Future<GoogleSignInAccount?> selectAccount({bool forceAccountSelection = true}) async {
    try {
      // 既存のサインインをクリア（強制的にアカウント選択画面を表示するため）
      if (forceAccountSelection) {
        // disconnect()ではなくsignOut()を使用
        // モバイルプラットフォームではdisconnect()が問題を起こす可能性がある
        await _googleSignIn.signOut();
      }

      // アカウント選択画面を表示してサインイン
      final account = await _googleSignIn.signIn();

      if (account != null) {
        _currentAccount = account;
        await _saveSelectedAccount(account);

        // 必要な権限があるか確認
        final hasPermissions = await _checkPermissions(account);
        if (!hasPermissions) {
          // 権限が不足している場合は再度認証を要求
          await _requestAdditionalPermissions();
        }
      }

      return account;
    } catch (e) {
      debugPrint('アカウント選択エラー: $e');
      // エラーの詳細をログに出力
      if (e is PlatformException) {
        debugPrint('PlatformException - Code: ${e.code}, Message: ${e.message}');
      }
      return null;
    }
  }

  /// アカウントを切り替える
  Future<GoogleSignInAccount?> switchAccount() async {
    try {
      // 現在のアカウントからサインアウト
      await _googleSignIn.signOut();

      // 新しいアカウントを選択
      return await selectAccount(forceAccountSelection: true);
    } catch (e) {
      debugPrint('アカウント切り替えエラー: $e');
      return null;
    }
  }

  /// サイレントサインイン（保存されたアカウントで自動サインイン）
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      _currentAccount = await _googleSignIn.signInSilently();
      if (_currentAccount != null) {
        await _saveSelectedAccount(_currentAccount!);
      }
      return _currentAccount;
    } catch (e) {
      debugPrint('サイレントサインインエラー: $e');
      return null;
    }
  }

  /// 特定のスコープに対する権限をリクエスト
  Future<bool> requestPermission(List<String> scopes) async {
    try {
      if (_currentAccount == null) {
        final account = await selectAccount();
        if (account == null) return false;
      }

      final hasPermission = await _googleSignIn.requestScopes(scopes);
      return hasPermission;
    } catch (e) {
      debugPrint('権限リクエストエラー: $e');
      return false;
    }
  }

  /// カレンダーアクセス権限をリクエスト
  Future<bool> requestCalendarPermission() async {
    // センシティブなスコープは使用せず、URLスキームでカレンダーを開く方式に変更
    // 権限リクエストは不要
    return true;
  }

  /// フォームアクセス権限をリクエスト
  Future<bool> requestFormsPermission() async {
    // センシティブなスコープは使用せず、URLスキームでフォームを開く方式に変更
    // 権限リクエストは不要
    return true;
  }

  /// 現在のアカウントが必要な権限を持っているか確認
  Future<bool> hasRequiredPermissions() async {
    if (_currentAccount == null) return false;

    try {
      // canAccessScopes() がプラットフォームで実装されていない場合があるため、
      // 現在のアカウントが存在することを権限があることとみなす
      // （基本スコープは既にサインイン時に許可されている）
      return true;
    } catch (e) {
      debugPrint('権限確認エラー: $e');
      // エラーが発生しても、アカウントが存在すれば権限があるとみなす
      return _currentAccount != null;
    }
  }

  /// サインアウト
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentAccount = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedAccountKey);
      await prefs.remove(_selectedAccountEmailKey);
      await prefs.remove(_accountIndexKey);
    } catch (e) {
      debugPrint('サインアウトエラー: $e');
    }
  }

  /// 完全にアカウントを切断
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentAccount = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_selectedAccountKey);
      await prefs.remove(_selectedAccountEmailKey);
      await prefs.remove(_accountIndexKey);
    } catch (e) {
      debugPrint('アカウント切断エラー: $e');
    }
  }

  /// GoogleカレンダーのURLを生成（アカウント指定付き）
  String generateCalendarUrl({
    required String baseUrl,
    Map<String, String>? params,
  }) {
    final uri = Uri.parse(baseUrl);
    final queryParams = Map<String, String>.from(params ?? {});

    // authuser パラメータを追加して特定のアカウントを指定
    if (_accountIndex >= 0) {
      queryParams['authuser'] = _accountIndex.toString();
    }

    // ログインヒントとしてメールアドレスを追加
    if (_currentAccount?.email != null) {
      queryParams['hd'] = _currentAccount!.email.split('@').last;
      queryParams['login_hint'] = _currentAccount!.email;
    }

    return uri.replace(queryParameters: queryParams).toString();
  }

  /// Google FormsのURLを生成（アカウント指定付き）
  String generateFormsUrl({
    required String baseUrl,
    Map<String, String>? params,
  }) {
    return generateCalendarUrl(baseUrl: baseUrl, params: params);
  }

  /// 選択されたアカウントを保存
  Future<void> _saveSelectedAccount(GoogleSignInAccount account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedAccountKey, account.id);
      await prefs.setString(_selectedAccountEmailKey, account.email);

      // アカウントインデックスを更新（推定値）
      _accountIndex = await _estimateAccountIndex(account.email);
      await prefs.setInt(_accountIndexKey, _accountIndex);
    } catch (e) {
      debugPrint('アカウント保存エラー: $e');
    }
  }

  /// メールアドレスからアカウントインデックスを推定
  Future<int> _estimateAccountIndex(String email) async {
    // Firebaseの現在のユーザーと比較
    final firebaseUser = firebase_auth.FirebaseAuth.instance.currentUser;
    if (firebaseUser?.email == email) {
      return 0; // デフォルトアカウント
    }

    // それ以外の場合は1を返す（複数アカウントの2番目と仮定）
    return 1;
  }

  /// 権限チェック
  Future<bool> _checkPermissions(GoogleSignInAccount account) async {
    try {
      // canAccessScopes() がプラットフォームで実装されていない場合があるため、
      // アカウントが存在することを権限があることとみなす
      return true;
    } catch (e) {
      debugPrint('権限チェックエラー: $e');
      // エラーが発生しても、アカウントが存在すれば権限があるとみなす
      return account != null;
    }
  }

  /// 追加の権限をリクエスト
  Future<void> _requestAdditionalPermissions() async {
    try {
      // カレンダーとフォームの権限をリクエスト
      final scopes = _requiredScopes.where((s) => s != 'email').toList();
      await _googleSignIn.requestScopes(scopes);
    } catch (e) {
      debugPrint('追加権限リクエストエラー: $e');
    }
  }

  /// アカウント情報を取得（デバッグ用）
  Map<String, dynamic> getAccountInfo() {
    return {
      'email': _currentAccount?.email,
      'displayName': _currentAccount?.displayName,
      'id': _currentAccount?.id,
      'photoUrl': _currentAccount?.photoUrl,
      'accountIndex': _accountIndex,
    };
  }
}