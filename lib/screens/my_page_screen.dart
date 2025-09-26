import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/experiment_service.dart';
import '../models/app_user.dart';
import '../widgets/custom_circle_avatar.dart';
import 'login_screen.dart';
import 'evaluation_history_screen.dart';
import 'history_screen.dart';
import 'icon_change_screen.dart';
import 'monthly_report_screen.dart';
import '../models/avatar_design.dart';
import '../models/avatar_color.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  AppUser? _currentUser;
  bool _isLoading = true;
  bool _isEditing = false;

  // 評価カウント用変数
  int _waitingOthersEvaluationCount = 0;
  int _unevaluatedCount = 0;
  int _scheduledCount = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _studentIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 画面に戻ってきた時にデータを再読み込み
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      var user = await _authService.getCurrentAppUser();
      if (user != null) {
        // scheduledExperimentsフィールドが存在しない場合は初期化
        await _userService.initializeScheduledExperimentsField(user.uid);

        // 初期化後、最新のユーザー情報を再取得
        user = await _authService.getCurrentAppUser();

        if (user != null) {
          // 評価カウントを計算
          await _calculateEvaluationCounts(user.uid);

          if (mounted) {
            setState(() {
              _currentUser = user;
              _nameController.text = user?.name ?? '';
              _bioController.text = user?.bio ?? '';
              _departmentController.text = user?.department ?? '';
              _gradeController.text = user?.grade ?? '';
              _studentIdController.text = user?.studentId ?? '';
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 評価カウントを計算
  Future<void> _calculateEvaluationCounts(String userId) async {
    try {
      // ExperimentServiceをインポートしていないので追加
      final experimentService = ExperimentService();
      final experiments = await experimentService.getUserParticipatedExperiments(userId);

      int waitingOthers = 0;
      int unevaluated = 0;
      int scheduled = 0;

      for (final experiment in experiments) {
        if (experiment.isScheduledFuture(userId)) {
          // 実施日時前の実験
          scheduled++;
        } else if (experiment.isWaitingOthersEvaluation(userId)) {
          // 自分は評価済みだが相手の評価待ち
          waitingOthers++;
        } else if (experiment.canEvaluateButNotYet(userId)) {
          // 評価可能だが未評価
          unevaluated++;
        }
      }

      if (mounted) {
        setState(() {
          _waitingOthersEvaluationCount = waitingOthers;
          _unevaluatedCount = unevaluated;
          _scheduledCount = scheduled;
        });
      }
    } catch (e) {
      // エラー時はカウントを0のまま
    }
  }

  Future<void> _saveProfile() async {
    if (_currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _userService.updateUserProfile(
        userId: _currentUser!.uid,
        name: _nameController.text.trim(),
        bio: _bioController.text.trim(),
        department: _departmentController.text.trim(),
        grade: _gradeController.text.trim(),
        studentId: _currentUser!.isWasedaUser ? _studentIdController.text.trim() : null,
      );

      await _loadUserData();
      
      if (mounted) {
        setState(() {
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プロフィールを更新しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  String _formatCurrency(int amount) {
    final formatter = amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return formatter;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8E1728)),
          ),
        ),
      );
    }

    if (_currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('ユーザー情報を取得できませんでした'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('マイページ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomCircleAvatar(
                              frameId: _currentUser!.selectedFrame,
                              radius: 35,
                              backgroundColor: _currentUser!.selectedColor != null
                                  ? AvatarColors.getById(_currentUser!.selectedColor!).color
                                  : const Color(0xFF8E1728),
                              designBuilder: _currentUser!.selectedDesign != null && _currentUser!.selectedDesign != 'default'
                                  ? AvatarDesigns.getById(_currentUser!.selectedDesign!).builder
                                  : null,
                              child: _currentUser!.selectedDesign == null || _currentUser!.selectedDesign == 'default'
                                  ? Text(
                                      _currentUser!.name.isNotEmpty 
                                        ? _currentUser!.name[0].toUpperCase() 
                                        : '?',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8E1728),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 12),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const IconChangeScreen(),
                                      ),
                                    ).then((_) => _loadUserData());
                                  },
                                  tooltip: 'フレームを変更',
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isEditing)
                          Column(
                            children: [
                              SizedBox(
                                width: 200,
                                child: TextField(
                                  controller: _nameController,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '名前を入力',
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    focusedBorder: const UnderlineInputBorder(
                                      borderSide: BorderSide(
                                        color: Color(0xFF8E1728),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = false;
                                        _nameController.text = _currentUser?.name ?? '';
                                        _bioController.text = _currentUser?.bio ?? '';
                                        _departmentController.text = _currentUser?.department ?? '';
                                        _gradeController.text = _currentUser?.grade ?? '';
                                        _studentIdController.text = _currentUser?.studentId ?? '';
                                      });
                                    },
                                    icon: const Icon(Icons.close, size: 16),
                                    label: const Text('キャンセル'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: _saveProfile,
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('保存'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8E1728),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentUser!.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                color: const Color(0xFF8E1728),
                                tooltip: '名前を編集',
                                onPressed: () {
                                  setState(() {
                                    _isEditing = true;
                                  });
                                },
                              ),
                            ],
                          ),
                        const SizedBox(height: 2),
                        Text(
                          _currentUser!.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 6),
                        // 学籍番号がある場合は表示
                        if (_currentUser!.studentId != null && _currentUser!.studentId!.isNotEmpty) ...[
                          Text(
                            '学籍番号: ${_currentUser!.studentId}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_currentUser!.isWasedaUser)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '早稲田大学',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Googleアカウント',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8E1728).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '完了実験数: ${_currentUser!.participatedExperiments}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8E1728),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // あなたの活動セクション
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'あなたの活動',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCompactActivityCard(
                                icon: Icons.hourglass_empty,
                                title: '評価待ち',
                                count: _waitingOthersEvaluationCount,
                                color: Colors.orange,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const HistoryScreen(),
                                    ),
                                  ).then((_) => _loadUserData());
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildCompactActivityCard(
                                icon: Icons.rate_review,
                                title: '未評価',
                                count: _unevaluatedCount,
                                color: Colors.red,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const HistoryScreen(),
                                    ),
                                  ).then((_) => _loadUserData());
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildCompactActivityCard(
                                icon: Icons.science,
                                title: '参加予定',
                                count: _scheduledCount,
                                color: Colors.blue,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const HistoryScreen(),
                                    ),
                                  ).then((_) => _loadUserData());
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 統計情報カード
                IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EvaluationHistoryScreen(
                                    userId: _currentUser!.uid,
                                    userName: _currentUser!.name,
                                    isMyHistory: true,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.thumb_up,
                                          color: Colors.green[700],
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          '評価統計',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(
                                      children: [
                                        Icon(
                                          Icons.thumb_up,
                                          color: Colors.green[600],
                                          size: 18,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_currentUser!.goodCount}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                        Text(
                                          'Good',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        Icon(
                                          Icons.thumb_down,
                                          color: Colors.red[600],
                                          size: 18,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_currentUser!.badCount}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[700],
                                          ),
                                        ),
                                        Text(
                                          'Bad',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Divider(color: Colors.grey[300], height: 1),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.stars,
                                          color: Colors.amber[600],
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '保有ポイント',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${_currentUser!.points.toInt()} P',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber[700],
                                      ),
                                    ),
                                  ],
                                ),
                                if (_currentUser!.goodCount + _currentUser!.badCount > 0) ...[
                                  const SizedBox(height: 4),
                                  Center(
                                    child: Text(
                                      '評価率: ${((_currentUser!.goodCount / (_currentUser!.goodCount + _currentUser!.badCount)) * 100).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                Center(
                                  child: Text(
                                    '詳細を見る',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: const Color(0xFF8E1728),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => MonthlyReportScreen(
                                    userId: _currentUser!.uid,
                                    userName: _currentUser!.name,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.payments,
                                            color: Colors.amber[700],
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            '収益統計',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '総収益',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '¥${_formatCurrency(_currentUser!.totalEarnings)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber[700],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '今月の収益',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '¥${_formatCurrency(_currentUser!.monthlyEarnings)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Center(
                                    child: Text(
                                      '月次レポート',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: const Color(0xFF8E1728),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'プロフィール情報',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (!_isEditing)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    color: const Color(0xFF8E1728),
                                    tooltip: '編集',
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = true;
                                      });
                                    },
                                  ),
                              ],
                            ),
                            if (_isEditing)
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isEditing = false;
                                        _nameController.text = _currentUser?.name ?? '';
                                        _bioController.text = _currentUser?.bio ?? '';
                                        _departmentController.text = _currentUser?.department ?? '';
                                        _gradeController.text = _currentUser?.grade ?? '';
                                      });
                                    },
                                    child: const Text('キャンセル'),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _saveProfile,
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // 学籍番号フィールド（早稲田ユーザーのみ表示）
                        if (_currentUser!.isWasedaUser) ...[
                          _buildProfileField(
                            label: '学籍番号',
                            controller: _studentIdController,
                            isEditing: _isEditing,
                            hintText: '例: 1G20XXXX',
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildProfileField(
                          label: '学部・学科',
                          controller: _departmentController,
                          isEditing: _isEditing,
                          hintText: '例: 政治経済学部',
                        ),
                        const SizedBox(height: 16),
                        _buildProfileField(
                          label: '学年',
                          controller: _gradeController,
                          isEditing: _isEditing,
                          hintText: '例: 3年',
                        ),
                        const SizedBox(height: 16),
                        _buildProfileField(
                          label: '自己紹介',
                          controller: _bioController,
                          isEditing: _isEditing,
                          hintText: '自己紹介を入力してください',
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_currentUser!.canCreateExperiment)
                  Card(
                    elevation: 2,
                    color: const Color(0xFF8E1728).withValues(alpha: 0.1),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified,
                            color: Color(0xFF8E1728),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '実験募集権限',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '早稲田大学のメールアドレスでログインしているため、実験を募集できます',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
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

  Widget _buildActivityCard({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActivityCard({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField({
    required String label,
    required TextEditingController controller,
    required bool isEditing,
    String? hintText,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        if (isEditing)
          TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              controller.text.isEmpty ? '未設定' : controller.text,
              style: TextStyle(
                fontSize: 16,
                color: controller.text.isEmpty ? Colors.grey : Colors.black,
              ),
            ),
          ),
      ],
    );
  }
    @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _departmentController.dispose();
    _gradeController.dispose();
    super.dispose();
  }
}
