import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../utils/constants.dart';

/// 支援・開発依頼画面
class SupportDonationScreen extends StatelessWidget {
  const SupportDonationScreen({super.key});

  /// 外部URLを開く
  Future<void> _launchUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);

    // 外部サイトへの移動を確認
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('外部サイトへ移動'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppConstants.externalLinkWarning),
            const SizedBox(height: 8),
            Text(
              url,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移動する'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('URLを開けませんでした'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('エラーが発生しました: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// PayPayアプリを開く
  Future<bool> _openPayPayApp(BuildContext context) async {
    try {
      // デバッグ情報
      debugPrint('Attempting to open PayPay app...');
      debugPrint('Platform: ${Platform.operatingSystem}');

      if (Platform.isAndroid) {
        // Android用の実装
        debugPrint('Android: Opening PayPay with AndroidIntent');

        // パッケージ名でアプリを起動
        const AndroidIntent intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          package: 'jp.ne.paypay.android.app',
        );

        // アプリがインストールされているかチェック
        if (await intent.canResolveActivity() ?? false) {
          await intent.launch();
          debugPrint('Android: PayPay app launched successfully');
          return true;
        } else {
          // アプリがインストールされていない場合、Play Storeを開く
          debugPrint('Android: PayPay app not found, opening Play Store');
          final playStoreUrl = Uri.parse('https://play.google.com/store/apps/details?id=jp.ne.paypay.android.app');
          if (await canLaunchUrl(playStoreUrl)) {
            await launchUrl(playStoreUrl, mode: LaunchMode.externalApplication);
          }
          return false;
        }
      } else if (Platform.isIOS) {
        // iOS用の実装
        debugPrint('iOS: Opening PayPay with URL scheme');

        // PayPayのURLスキーム
        final payPayUrl = Uri.parse('paypay://');

        if (await canLaunchUrl(payPayUrl)) {
          final launched = await launchUrl(
            payPayUrl,
            mode: LaunchMode.externalApplication,
          );
          debugPrint('iOS: PayPay app launch result: $launched');
          return launched;
        } else {
          // アプリがインストールされていない場合、App Storeを開く
          debugPrint('iOS: PayPay app not found, opening App Store');
          final appStoreUrl = Uri.parse('https://apps.apple.com/jp/app/paypay/id1435783608');
          if (await canLaunchUrl(appStoreUrl)) {
            await launchUrl(appStoreUrl, mode: LaunchMode.externalApplication);
          }
          return false;
        }
      } else {
        // Web/その他のプラットフォーム
        debugPrint('Web/Other: Opening PayPay website');
        final webUrl = Uri.parse('https://paypay.ne.jp/');
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error opening PayPay app: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('PayPayアプリを開けませんでした: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
      return false;
    }
  }

  /// PayPayで支援ダイアログを表示
  Future<void> _showPayPayDialog(BuildContext context) async {
    bool idCopied = false;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 20 : 16),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 500,
              minHeight: 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ヘッダー
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B900).withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  padding: EdgeInsets.all(isMobile ? 20 : 24),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(isMobile ? 10 : 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.payment,
                          color: const Color(0xFF00B900),
                          size: isMobile ? 28 : 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PayPayで支援',
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ID検索でかんたん送金',
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // コンテンツ
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isMobile ? 20 : 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Step 1: IDをコピー - モバイル最適化
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                idCopied
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : const Color(0xFF00B900).withValues(alpha: 0.05),
                                idCopied
                                    ? Colors.green.withValues(alpha: 0.05)
                                    : const Color(0xFF00B900).withValues(alpha: 0.02),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: idCopied
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : const Color(0xFF00B900).withValues(alpha: 0.2),
                              width: idCopied ? 2 : 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: idCopied ? null : () async {
                                await Clipboard.setData(
                                  ClipboardData(text: AppConstants.payPayId),
                                );
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  idCopied = true;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('IDをコピーしました'),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  );
                                }

                                // 少し待ってからPayPayアプリを開く
                                await Future.delayed(const Duration(milliseconds: 500));
                                await _openPayPayApp(context);
                              },
                              child: Padding(
                                padding: EdgeInsets.all(isMobile ? 16 : 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // ステップインジケーター
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: isMobile ? 32 : 36,
                                          height: isMobile ? 32 : 36,
                                          decoration: BoxDecoration(
                                            color: idCopied
                                                ? Colors.green
                                                : const Color(0xFF00B900),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Icon(
                                              idCopied ? Icons.check : Icons.copy,
                                              color: Colors.white,
                                              size: isMobile ? 18 : 20,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          idCopied ? 'コピー完了！' : 'タップしてIDをコピー',
                                          style: TextStyle(
                                            fontSize: isMobile ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: idCopied ? Colors.green : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: isMobile ? 16 : 20),

                                    // ID表示エリア
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isMobile ? 16 : 20,
                                        vertical: isMobile ? 12 : 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.person,
                                            size: isMobile ? 20 : 24,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            AppConstants.payPayId,
                                            style: TextStyle(
                                              fontSize: isMobile ? 18 : 20,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            idCopied ? Icons.check_circle : Icons.copy,
                                            size: isMobile ? 20 : 24,
                                            color: idCopied ? Colors.green : Colors.grey[400],
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (!idCopied) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'ワンタップでコピー',
                                        style: TextStyle(
                                          fontSize: isMobile ? 11 : 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: isMobile ? 20 : 24),

                        // Step 2: 送金手順 - シンプル化
                        Container(
                          padding: EdgeInsets.all(isMobile ? 16 : 20),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: isMobile ? 28 : 32,
                                    height: isMobile ? 28 : 32,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[400],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '2',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isMobile ? 14 : 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'PayPayで送金',
                                    style: TextStyle(
                                      fontSize: isMobile ? 15 : 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isMobile ? 12 : 16),

                              // 手順を見やすく
                              ...List.generate(5, (index) {
                                final steps = [
                                  'PayPayアプリを開く',
                                  '「送る」をタップ',
                                  '「PayPay ID/携帯番号」を選択',
                                  'コピーしたIDを貼り付け',
                                  '金額を入力して送金',
                                ];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        width: 20,
                                        child: Text(
                                          '${index + 1}.',
                                          style: TextStyle(
                                            fontSize: isMobile ? 12 : 13,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          steps[index],
                                          style: TextStyle(
                                            fontSize: isMobile ? 13 : 14,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        SizedBox(height: isMobile ? 20 : 24),

                        // PayPayアプリを開くボタン - 大きくて押しやすく
                        ElevatedButton.icon(
                          onPressed: () async {
                            final opened = await _openPayPayApp(context);
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('PayPayアプリが見つかりません'),
                                    ],
                                  ),
                                  backgroundColor: Colors.orange,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.launch),
                          label: Text(
                            'PayPayアプリを開く',
                            style: TextStyle(fontSize: isMobile ? 15 : 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B900),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isMobile ? 14 : 16,
                              horizontal: isMobile ? 24 : 32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 注意書き
                        Center(
                          child: Text(
                            'アプリがインストールされている場合のみ開きます',
                            style: TextStyle(
                              fontSize: isMobile ? 11 : 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('支援・開発のご依頼'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 支援セクション
            Container(
              color: const Color(0xFF8E1728).withValues(alpha: 0.05),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.favorite,
                    size: 48,
                    color: Color(0xFF8E1728),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'サービス運営への支援',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    AppConstants.donationMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showPayPayDialog(context),
                        icon: const Icon(Icons.payment),
                        label: const Text('PayPayで支援'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B900),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _launchUrl(context, AppConstants.githubSponsorsUrl),
                        icon: const Icon(Icons.code),
                        label: const Text('GitHub'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 開発依頼セクション
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.code,
                        size: 32,
                        color: Color(0xFF8E1728),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '開発のご依頼',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    AppConstants.developmentServiceMessage,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // サービス内容カード
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '承っている開発案件',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildServiceItem(
                            Icons.science,
                            '研究用システムの開発',
                            '実験管理、データ収集、分析ツールなど',
                          ),
                          _buildServiceItem(
                            Icons.work,
                            '就活用マイページの作成',
                            'ポートフォリオサイト、自己PR用Webページなど',
                          ),
                          _buildServiceItem(
                            Icons.web,
                            'Webアプリケーション開発',
                            'Webサービス、管理画面、APIの構築など',
                          ),
                          _buildServiceItem(
                            Icons.phone_android,
                            'モバイルアプリ開発',
                            'iOS/Android対応のネイティブ・クロスプラットフォームアプリ',
                          ),
                          _buildServiceItem(
                            Icons.more_horiz,
                            'その他の開発案件',
                            'お客様のニーズに合わせた柔軟な対応が可能です',
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // お問い合わせボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchUrl(context, AppConstants.developmentRequestFormUrl),
                      icon: const Icon(Icons.mail_outline),
                      label: const Text(
                        '開発のご相談・お見積もり（無料）',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8E1728),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // 注意事項
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Colors.blue[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'お問い合わせフォームは外部サイト（Googleフォーム）へ移動します。'
                            'ご相談・お見積もりは無料です。お気軽にお問い合わせください。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // フッター
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    '© 2025 ${AppConstants.teamName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'わせラボは早稲田大学の公式サービスではありません',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 24,
            color: const Color(0xFF8E1728),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}