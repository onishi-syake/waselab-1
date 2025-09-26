import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/google_calendar_service.dart';
import '../services/google_forms_service.dart';
import '../services/google_account_service.dart';
import 'login_screen.dart';
import 'support_chat_screen.dart';
import 'support_donation_screen.dart';

/// 設定画面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final FCMService _fcmService = FCMService();
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  final GoogleAccountService _accountService = GoogleAccountService();

  // 通知設定
  bool _experimentNotifications = true;
  bool _messageNotifications = true;
  bool _emailNotifications = false;

  // カレンダー連携設定
  bool _calendarEnabled = false;
  bool _calendarConnected = false;

  // Googleアカウント情報
  String? _currentGoogleAccount;
  Map<String, dynamic>? _accountInfo;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
    _loadSettings();
  }

  Future<void> _initializeServices() async {
    // エラーハンドラーを設定
    _calendarService.onError = _handleGoogleServiceError;
    GoogleFormsService.onError = _handleGoogleServiceError;

    // アカウントサービスを初期化
    await _accountService.initialize();
    _loadAccountInfo();
  }

  void _handleGoogleServiceError(String error, bool needsAccountSelection) {
    if (!mounted) return;

    if (needsAccountSelection) {
      // アカウント選択が必要な場合
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('アカウントの選択が必要'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _selectGoogleAccount();
              },
              child: const Text('アカウントを選択'),
            ),
          ],
        ),
      );
    } else {
      // その他のエラー
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: '再試行',
            textColor: Colors.white,
            onPressed: () => _loadSettings(),
          ),
        ),
      );
    }
  }

  Future<void> _loadAccountInfo() async {
    final info = _calendarService.getCurrentAccountInfo();
    if (mounted) {
      setState(() {
        _accountInfo = info;
        _currentGoogleAccount = info?['email'];
      });
    }
  }

  Future<void> _selectGoogleAccount() async {
    try {
      // アカウント選択前にローディングインジケータを表示
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final account = await _accountService.selectAccount(forceAccountSelection: true);

      // ローディングインジケータを閉じる
      if (mounted) {
        Navigator.pop(context);
      }

      if (account != null) {
        // カレンダーとフォームの権限をリクエスト
        final calendarPermission = await _accountService.requestCalendarPermission();
        final formsPermission = await _accountService.requestFormsPermission();

        // Firestoreのユーザー情報を更新してGoogleアカウントのメールを保存
        final user = _authService.currentUser;
        if (user != null) {
          await _authService.updateGoogleEmail(user.uid, account.email);
        }

        if (mounted) {
          if (calendarPermission || formsPermission) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${account.email} でログインしました'),
                backgroundColor: Colors.green,
              ),
            );
            _loadAccountInfo();
            _loadSettings();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('必要な権限が付与されませんでした'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        // ユーザーがキャンセルした場合
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('アカウント選択がキャンセルされました'),
              backgroundColor: Colors.grey,
            ),
          );
        }
      }
    } catch (e) {
      // ローディングインジケータが表示されている場合は閉じる
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        // エラーの詳細をログに出力
        debugPrint('Google Sign-In Error: $e');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('アカウント選択エラー: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _switchGoogleAccount() async {
    try {
      final success = await _calendarService.switchAccount();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('アカウントを切り替えました'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAccountInfo();
        _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('アカウント切り替えエラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
    }
  }
  
  Future<void> _loadSettings() async {
    // 通知設定を読み込み
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _experimentNotifications = prefs.getBool('experiment_notifications') ?? true;
        _messageNotifications = prefs.getBool('message_notifications') ?? true;
        _emailNotifications = prefs.getBool('email_notifications') ?? false;
      });
    }
    
    // カレンダー設定を読み込み
    await _loadCalendarSettings();
  }
  
  Future<void> _saveNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('experiment_notifications', _experimentNotifications);
    await prefs.setBool('message_notifications', _messageNotifications);
    await prefs.setBool('email_notifications', _emailNotifications);
  }
  
  Future<void> _loadCalendarSettings() async {
    try {
      // まず保存された設定を読み込む
      final enabled = await _calendarService.isCalendarEnabled();

      // 接続状態を確認（enabledの値に関わらず）
      final connected = await _calendarService.hasCalendarPermission();

      // Googleアカウント情報を読み込み
      _loadAccountInfo();

      if (mounted) {
        setState(() {
          _calendarEnabled = enabled;
          _calendarConnected = connected;
        });
      } else {
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _calendarEnabled = false;
          _calendarConnected = false;
        });
      }
    }
  }
  
  /// ログアウト処理
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしてもよろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _authService.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }
  
  /// お問い合わせを開く
  void _openSupport() {
    // サポートチャット画面に遷移
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SupportChatScreen()),
    );
  }
  
  /// 利用規約を開く
  void _openTermsOfService() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('利用規約'),
        content: const SingleChildScrollView(
          child: Text(
            '利用規約\n\n'
            '本利用規約（以下「本規約」）は、本アプリケーション（以下「本アプリ」）の利用条件を定めるものです。利用者は、本アプリを利用することにより、本規約に同意したものとみなされます。\n\n'
            '第1条（適用範囲・定義）\n'
            '1. 本規約は、利用者と本アプリの運営者（以下「運営者」）との間の一切の関係に適用されます。\n'
            '2. 本規約において、以下の用語は次の意味を有します。\n'
            '   - 「利用者」：本アプリを利用する全ての者\n'
            '   - 「実験者」：本アプリにおいて研究実験の募集を行う者\n'
            '   - 「被験者」：実験に応募し、参加を希望する者\n\n'
            '第2条（アカウント登録・ログイン）\n'
            '1. 利用者は、メールアドレスまたは外部サービス（Googleアカウント等）を用いて登録を行うものとします。\n'
            '2. 利用者は、登録情報について真実かつ正確な情報を提供する義務を負います。\n'
            '3. 未成年者が利用する場合、保護者の同意を得るものとします。\n\n'
            '第3条（利用条件）\n'
            '1. 本アプリは、実験者と被験者をつなぐプラットフォームであり、研究実験そのものを実施する場ではありません。\n'
            '2. 実験の内容、倫理性、安全性、データ管理については、各実験者が責任を負います。\n'
            '3. 被験者は、自らの判断と責任において応募・参加するものとします。\n\n'
            '第4条（禁止事項）\n'
            '利用者は、以下の行為をしてはなりません。\n'
            '1. 法令または公序良俗に違反する行為\n'
            '2. 虚偽の情報を登録する行為\n'
            '3. 実験募集に関する不正行為（虚偽募集、無断キャンセル等）\n'
            '4. 他者への誹謗中傷、ハラスメント行為\n'
            '5. チャット機能での迷惑行為、スパム行為\n'
            '6. 運営者または第三者の知的財産権・プライバシー権を侵害する行為\n'
            '7. その他、運営者が不適切と判断する行為\n\n'
            '第5条（実験者・被験者の責任）\n'
            '1. 実験者は、募集内容について正確かつ誠実に説明し、必要に応じて倫理審査を経るものとします。\n'
            '2. 実験者は、被験者の安全と権利を尊重し、適切な研究実施責任を負います。\n'
            '3. 被験者は、応募・参加に伴うリスクを理解し、自らの判断で参加するものとします。\n'
            '4. 運営者は、実験内容や研究成果に関する責任を一切負いません。\n\n'
            '第6条（違反行為に対する措置）\n'
            '1. 運営者は、利用者が本規約に違反したと判断した場合、事前の通知なく以下のいずれかまたは複数の措置を講じることができます。\n'
            '   - 警告または注意喚起\n'
            '   - チャット機能その他一部機能の利用制限\n'
            '   - アカウントの一時停止\n'
            '   - アカウントの削除および再登録の禁止\n'
            '2. 利用者の違反行為によって運営者または第三者に損害が生じた場合、利用者はその賠償責任を負うものとします。\n'
            '3. 違反行為が法令に抵触すると判断される場合、運営者は警察その他関係当局に通報することがあります。\n\n'
            '第7条（サービスの変更・中断・終了）\n'
            '1. 運営者は、事前の通知なく本アプリの内容を変更できるものとします。\n'
            '2. システム障害、法令改正、その他やむを得ない事由により、本アプリの提供を中断・終了することがあります。\n\n'
            '第8条（免責事項）\n'
            '1. 運営者は、実験内容の正確性、安全性、倫理性について保証しません。\n'
            '2. 利用者間で生じたトラブルについて、運営者は一切責任を負いません。\n'
            '3. 運営者は、本アプリの利用に関連して利用者に生じたいかなる損害についても一切責任を負いません。\n'
            '4. ただし、適用法令上免責が認められない場合には、この限りではありません。\n\n'
            '第9条（知的財産権）\n'
            '1. 本アプリに関する著作権、商標権等の知的財産権は運営者に帰属します。\n'
            '2. 利用者が投稿・登録した情報については、本アプリの運営に必要な範囲で利用できるものとします。\n\n'
            '第10条（アカウント停止・削除）\n'
            '1. 運営者は、利用者が本規約に違反した場合、アカウントを停止または削除することができます。\n'
            '2. 利用者が一定期間ログインしない場合、運営者はアカウントを削除できるものとします。\n\n'
            '第11条（利用料金）\n'
            '1. 本アプリの基本利用は無料とします。ただし、有料サービスを導入する場合、その条件を別途定めます。\n'
            '2. 有料サービスの利用料金、支払方法、返金条件は別途案内します。\n\n'
            '第12条（規約の変更）\n'
            '1. 運営者は、必要に応じて本規約を改訂することができます。\n'
            '2. 重要な変更を行う場合は、事前に通知するものとします。\n\n'
            '第13条（準拠法・裁判管轄）\n'
            '1. 本規約は、日本法に準拠します。\n'
            '2. 本アプリに関して紛争が生じた場合、東京簡易裁判所または東京地方裁判所を専属的合意管轄とします。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
  
  /// プライバシーポリシーを開く
  void _openPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プライバシーポリシー'),
        content: const SingleChildScrollView(
          child: Text(
            'プライバシーポリシー\n\n'
            '本アプリケーション（以下「本アプリ」）は、研究実験の実施者（以下「実験者」）と実験協力希望者（以下「被験者」）をつなぐプラットフォームです。利用者の個人情報を適切に保護するため、以下の方針を定めます。\n\n'
            '1. 収集する情報\n'
            '本アプリでは、以下の情報を収集する場合があります。\n'
            '- アカウント登録時の情報（氏名、性別、年齢、メールアドレス、パスワード、googleアカウントからの情報等）\n'
            '- プロフィール情報（学部・学科、学年、自己紹介）\n'
            '- 募集作成・応募時の情報（実験日程や実験場所などの実験募集において必要な情報、実験の参加日程や応募条件に応じた追加項目など）\n'
            '- チャット機能で送受信されるメッセージ内容\n'
            '- 技術的情報（アクセスログ、IPアドレス、Cookie、端末情報等）\n\n'
            'Googleアカウントによるログインについて\n'
            '本アプリでは、Googleアカウントを利用したログイン機能を提供しています。Googleログインを利用する場合、氏名（Googleアカウントの表示名）とメールアドレスをGoogleから取得します。これらの情報は、アカウント登録・認証および利用者との連絡のために使用します。取得した情報を第三者に提供することはありません（法令に基づく場合を除きます）。また、本アプリは Google API Services User Data Policy に準拠して運営されています。\n\n'
            '2. 利用目的\n'
            '収集した情報は、以下の目的で利用します。\n'
            '- 実験者と被験者のマッチング、応募管理、連絡調整のため\n'
            '- チャット機能によるコミュニケーション提供のため\n'
            '- 実験者の信頼性確保のための本人確認・審査のため\n'
            '- 利用者へのリマインド通知やアンケート送信のため\n'
            '- 本アプリの運営、機能改善、セキュリティ対策のため\n'
            '- 法令に基づく義務の履行および不正利用防止のため\n'
            '※本アプリは研究データ自体を収集・管理しません。研究データは各実験者が責任を持って管理します。\n\n'
            '3. 第三者提供\n'
            '本アプリは、以下の場合を除き、利用者の個人情報を第三者に提供しません。\n'
            '- ご本人の同意がある場合\n'
            '- 法令に基づく場合\n'
            '- 匿名化または統計化した情報を開示する場合\n'
            '※実験者と被験者の間で交換される情報は、当事者間の責任において利用されます。\n\n'
            '4. チャット機能の取扱い\n'
            '- チャット内容は、利用者間の円滑なコミュニケーションを目的として提供されます。\n'
            '- 安全管理・不正利用防止・トラブル対応のため、運営がチャット内容を確認する場合があります。\n'
            '- ハラスメントや迷惑行為が確認された場合、運営はチャット内容を削除し、利用制限を行うことがあります。\n\n'
            '5. データの管理\n'
            '- データは暗号化通信により送受信されます。\n'
            '- アクセス権限は、必要最小限の管理者のみに付与されます。\n\n'
            '6. 利用者の権利\n'
            '利用者は、自身の個人情報について以下の権利を有します。\n'
            '- 開示、訂正、削除、利用停止の請求\n'
            '- 研究参加に関する同意の撤回\n'
            '請求は、アプリ内フォームまたはメールで受け付けます。未成年者は、保護者の同意が必要です。\n\n'
            '7. クッキー等の利用\n'
            '- 本アプリでは、利便性向上や利用状況分析のためにCookieを使用します。\n'
            '- Google Analytics等の外部解析ツールを利用する場合、そのサービス名と利用目的を明示します。\n'
            '- 広告目的のCookie利用がある場合は、オプトアウトの方法を提供します。\n\n'
            '8. 法的基盤\n'
            '- 本アプリは、日本の個人情報保護法を遵守します。\n'
            '- 大学や研究機関との契約に基づき、追加の遵守事項が発生する場合があります。\n\n'
            '9. お問い合わせ先\n'
            'プライバシーポリシーに関するご質問や請求は、以下の窓口までご連絡ください。\n'
            '- 開発元：わせラボチーム\n'
            '- 責任者名：宮本 雄大\n'
            '- メールアドレス：yudai61104@gmail.com\n\n'
            '10. 改訂\n'
            '- 本ポリシーは必要に応じて改訂されます。\n'
            '- 改訂内容は、アプリ内通知またはメールにて利用者に告知します。\n'
            '- 重要な変更を行う場合は、原則として30日前に告知します。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: [
          // 通知設定セクション
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '通知設定',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('実験に関する通知'),
                  subtitle: const Text('新しい実験募集、参加実験の更新など'),
                  value: _experimentNotifications,
                  onChanged: (value) async {
                    setState(() {
                      _experimentNotifications = value;
                    });
                    await _saveNotificationSettings();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('メッセージ通知'),
                  subtitle: const Text('新着メッセージの通知'),
                  value: _messageNotifications,
                  onChanged: (value) async {
                    setState(() {
                      _messageNotifications = value;
                    });
                    await _saveNotificationSettings();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('メール通知'),
                  subtitle: const Text('重要なお知らせをメールで受け取る'),
                  value: _emailNotifications,
                  onChanged: (value) async {
                    setState(() {
                      _emailNotifications = value;
                    });
                    await _saveNotificationSettings();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active),
                  title: const Text('プッシュ通知テスト'),
                  subtitle: const Text('プッシュ通知が正常に動作するかテストします'),
                  trailing: const Icon(Icons.send),
                  onTap: () async {
                    try {
                      await _fcmService.sendTestNotification();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('テスト通知を送信しました'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('通知の送信に失敗しました: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // Google連携セクション
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Google連携',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),

          // Googleアカウント情報
          if (_currentGoogleAccount != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.account_circle, color: Colors.white),
                ),
                title: const Text('Googleアカウント'),
                subtitle: Text(_currentGoogleAccount!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      onPressed: _switchGoogleAccount,
                      tooltip: 'アカウントを切り替え',
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        await _accountService.signOut();
                        _loadAccountInfo();
                        _loadSettings();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Googleアカウントからログアウトしました'),
                            ),
                          );
                        }
                      },
                      tooltip: 'ログアウト',
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.account_circle, color: Colors.white),
                ),
                title: const Text('Googleアカウント'),
                subtitle: const Text('未接続'),
                trailing: ElevatedButton(
                  onPressed: _selectGoogleAccount,
                  child: const Text('アカウントを選択'),
                ),
              ),
            ),

          const SizedBox(height: 8),

          // カレンダー連携
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Googleカレンダー連携'),
                  subtitle: Text(_calendarConnected
                    ? (_calendarEnabled ? 'カレンダーと連携済み' : 'カレンダー連携は無効です')
                    : 'カレンダーと連携していません'),
                  value: _calendarEnabled,
                  onChanged: (value) async {
                    if (value) {
                      // カレンダー連携を有効にする
                      if (!_calendarConnected) {
                        // まだ認証していない場合は認証を行う
                        final success = await _calendarService.requestCalendarPermission(
                          forceAccountSelection: _currentGoogleAccount == null
                        );
                        if (success) {
                          await _calendarService.setCalendarEnabled(true);
                          if (mounted) {
                            setState(() {
                              _calendarEnabled = true;
                              _calendarConnected = true;
                            });
                            _loadAccountInfo();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Googleカレンダーと連携しました'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('カレンダー連携に失敗しました'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } else {
                        // すでに認証済みの場合は有効化のみ
                        await _calendarService.setCalendarEnabled(true);
                        setState(() {
                          _calendarEnabled = true;
                        });
                      }
                    } else {
                      // カレンダー連携を無効にする（接続は維持）
                      await _calendarService.setCalendarEnabled(false);
                      setState(() {
                        _calendarEnabled = false;
                      });
                    }
                  },
                ),
                if (_calendarConnected && _calendarEnabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.link_off, color: Colors.red),
                    title: const Text('カレンダー連携を解除'),
                    subtitle: const Text('Googleカレンダーとの連携を解除します'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('カレンダー連携の解除'),
                          content: const Text(
                            'Googleカレンダーとの連携を解除しますか？\n'
                            '解除後も既にカレンダーに追加された予定は残ります。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('解除', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirmed == true) {
                        await _calendarService.disconnectCalendar();
                        if (mounted) {
                          setState(() {
                            _calendarEnabled = false;
                            _calendarConnected = false;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('カレンダー連携を解除しました'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('カレンダー連携について'),
                  subtitle: Text(
                    '実験の予約時に自動でGoogleカレンダーに予定を追加できます。'
                    'キャンセル時は手動でカレンダーから削除してください。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // アカウント設定セクション
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'アカウント',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('パスワード変更'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final email = _authService.currentUser?.email;
                    if (email != null) {
                      final result = await _authService.sendPasswordResetEmail(email);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result ?? 'パスワードリセットメールを送信しました'),
                            backgroundColor: result == null ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('アカウント削除', style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('アカウント削除'),
                        content: const Text(
                          'アカウントを削除すると、すべてのデータが失われます。\n'
                          'この操作は取り消すことができません。\n\n'
                          '本当に削除しますか？',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('キャンセル'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('アカウント削除機能は現在準備中です'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            child: const Text('削除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // サポートセクション
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'サポート',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('ヘルプ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('ヘルプ'),
                        content: const Text(
                          'わせラボの使い方\n\n'
                          '1. 実験を探す\n'
                          'ホーム画面から興味のある実験を探しましょう。\n\n'
                          '2. 実験に参加\n'
                          '詳細を確認して「参加する」ボタンから申し込みます。\n\n'
                          '3. メッセージで連絡\n'
                          '実験者とメッセージでやり取りできます。\n\n'
                          'お困りの場合は「お問い合わせ」からご連絡ください。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('閉じる'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('お問い合わせ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openSupport,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.volunteer_activism, color: Color(0xFF8E1728)),
                  title: const Text('支援・開発のご依頼'),
                  subtitle: const Text('サービス運営への支援と開発案件のご相談'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF8E1728)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SupportDonationScreen()),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('利用規約'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openTermsOfService,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('プライバシーポリシー'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openPrivacyPolicy,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // その他セクション
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'その他',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('バージョン情報'),
                  subtitle: const Text('Version 1.0.0'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'わせラボ',
                      applicationVersion: '1.0.0',
                      applicationIcon: const Icon(
                        Icons.science,
                        size: 48,
                        color: Color(0xFF8E1728),
                      ),
                      children: const [
                        Text(
                          '早稲田大学実験協力プラットフォーム\n\n'
                          '【重要】\n'
                          'このアプリは早稲田大学の公式アプリではありません。\n'
                          '学生有志により開発・運営されています。\n\n'
                          '© 2025 WaseLab Team',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('ログアウト', style: TextStyle(color: Colors.red)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.red),
                  onTap: _handleLogout,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}