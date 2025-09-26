import 'package:flutter/material.dart';
import '../screens/support_donation_screen.dart';
import '../screens/settings_screen.dart';
import '../models/app_user.dart';

/// ナビゲーションドロワーWidget
class NavigationDrawerWidget extends StatelessWidget {
  final AppUser? currentUser;
  
  const NavigationDrawerWidget({
    super.key,
    this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // ヘッダー部分
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8E1728),
                  Color(0xFFB91C2C),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.science,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 8),
                const Text(
                  'わせラボ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentUser?.name ?? 'ゲスト',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                Text(
                  currentUser?.email ?? '',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          
          // メニューアイテム
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 支援・開発のご依頼（目立つデザイン）
                Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF8E1728).withValues(alpha: 0.1),
                        const Color(0xFF8E1728).withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8E1728).withValues(alpha: 0.2),
                    ),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.volunteer_activism,
                      color: Color(0xFF8E1728),
                      size: 28,
                    ),
                    title: const Text(
                      '支援・開発のご依頼',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: const Text(
                      'サービス運営への支援と開発案件',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E1728),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // ドロワーを閉じる
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SupportDonationScreen(),
                        ),
                      );
                    },
                  ),
                ),
                
                const Divider(),
                
                // 通常のメニューアイテム
                ListTile(
                  leading: const Icon(Icons.home),
                  title: const Text('ホーム'),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('マイページ'),
                  onTap: () {
                    Navigator.pop(context);
                    // マイページへの遷移処理
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.message),
                  title: const Text('メッセージ'),
                  onTap: () {
                    Navigator.pop(context);
                    // メッセージ画面への遷移処理
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: const Text('通知'),
                  onTap: () {
                    Navigator.pop(context);
                    // 通知画面への遷移処理
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('履歴'),
                  onTap: () {
                    Navigator.pop(context);
                    // 履歴画面への遷移処理
                  },
                ),
                
                const Divider(),
                
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('設定'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('ヘルプ'),
                  onTap: () {
                    Navigator.pop(context);
                    // ヘルプ画面への遷移処理
                  },
                ),
              ],
            ),
          ),
          
          // フッター部分
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(
                top: BorderSide(
                  color: Colors.grey[300]!,
                ),
              ),
            ),
            child: Column(
              children: [
                Text(
                  'わせラボ v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2025 WaseLab Team',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
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