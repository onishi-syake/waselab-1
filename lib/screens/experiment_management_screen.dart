import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/experiment.dart';
import '../models/app_user.dart';
import '../services/experiment_service.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/flexible_schedule_service.dart';
import '../services/google_calendar_service.dart';
import '../services/message_service.dart';
import '../widgets/custom_circle_avatar.dart';
import '../models/avatar_design.dart';
import 'chat_screen.dart';
import 'experiment_detail_screen.dart';
import 'experiment_evaluation_screen.dart';

/// 実験管理画面
/// 実験募集者が自分の実験を管理するための画面
class ExperimentManagementScreen extends StatefulWidget {
  final Experiment experiment;

  const ExperimentManagementScreen({
    super.key,
    required this.experiment,
  });

  @override
  State<ExperimentManagementScreen> createState() => _ExperimentManagementScreenState();
}

class _ExperimentManagementScreenState extends State<ExperimentManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExperimentService _experimentService = ExperimentService();
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final FlexibleScheduleService _scheduleService = FlexibleScheduleService();
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  final MessageService _messageService = MessageService();

  late Experiment _experiment;
  List<AppUser> _participants = [];
  bool _isLoading = true;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _experiment = widget.experiment;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 現在のユーザー情報を取得
      _currentUser = await _authService.getCurrentAppUser();
      
      // 最新の実験情報を取得
      final updatedExperiment = await _experimentService.getExperimentById(_experiment.id);
      if (updatedExperiment != null) {
        _experiment = updatedExperiment;
      }
      
      // 参加者情報を取得
      final participantsList = <AppUser>[];
      for (final participantId in _experiment.participants) {
        final user = await _userService.getUserById(participantId);
        if (user != null) {
          participantsList.add(user);
        }
      }
      
      if (mounted) {
        setState(() {
          _participants = participantsList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ステータス変更機能は削除（システムが自動管理するため）
  // 実験の流れ:
  // 1. 募集中: 募集期限内
  // 2. 進行中: 実験期間中
  // 3. 評価待ち/完了: 参加者ごとに個別管理

  /// 実験後アンケートURLが送信済みかチェック
  bool _hasPostSurveyUrlSent(String participantId) {
    final experimentData = _experiment.toFirestore();
    final participantEvals = experimentData['participantEvaluations'] as Map<String, dynamic>? ?? {};
    final userEval = participantEvals[participantId] as Map<String, dynamic>? ?? {};
    return userEval['postSurveyUrlSent'] ?? false;
  }

  /// 実験後アンケートURLを送信
  Future<void> _sendPostSurveyUrl(AppUser participant) async {
    if (_experiment.postSurveyUrl == null || _experiment.postSurveyUrl!.isEmpty) {
      return;
    }

    // 既に送信済みの場合は確認ダイアログを表示
    if (_hasPostSurveyUrlSent(participant.uid)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('確認'),
          content: const Text('このユーザーには既にアンケートURLを送信済みです。\n再度送信しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8E1728),
              ),
              child: const Text('再送信'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      // 通知を作成
      await _experimentService.sendPostSurveyUrlNotification(
        experimentId: _experiment.id,
        participantId: participant.uid,
        participantName: participant.name,
        experimentTitle: _experiment.title,
        surveyUrl: _experiment.postSurveyUrl!,
      );

      // 送信状態を更新
      await _experimentService.updatePostSurveyUrlSentStatus(
        experimentId: _experiment.id,
        participantId: participant.uid,
        sent: true,
      );

      // データを再読み込み
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${participant.name}にアンケートURLを送信しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('送信に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// URL送信可能な参加者数を取得
  int _getUrlSendableParticipantCount() {
    if (_experiment.postSurveyUrl == null || _experiment.postSurveyUrl!.isEmpty) {
      return 0;
    }

    int count = 0;
    final experimentData = _experiment.toFirestore();
    final participantEvals = experimentData['participantEvaluations'] as Map<String, dynamic>? ?? {};

    for (final participantId in _experiment.participants) {
      final userEval = participantEvals[participantId] as Map<String, dynamic>? ?? {};
      final urlSent = userEval['postSurveyUrlSent'] ?? false;
      if (!urlSent) {
        count++;
      }
    }

    return count;
  }

  /// 評価可能な参加者数を取得
  int _getEvaluatableParticipantCount() {
    int count = 0;
    final experimentData = _experiment.toFirestore();
    final participantEvals = experimentData['participantEvaluations'] as Map<String, dynamic>? ?? {};
    
    // 実験が実施日時を迎えているかチェック
    bool isExperimentStarted = false;
    
    if (_experiment.allowFlexibleSchedule) {
      // 柔軟なスケジュールの場合（予約制）
      // 実験期間が開始していれば評価可能
      if (_experiment.experimentPeriodStart != null) {
        isExperimentStarted = DateTime.now().isAfter(_experiment.experimentPeriodStart!);
      } else {
        // 期間が設定されていない場合は常に評価可能
        isExperimentStarted = true;
      }
    } else if (_experiment.fixedExperimentDate != null) {
      // 固定日時の場合
      isExperimentStarted = DateTime.now().isAfter(_experiment.fixedExperimentDate!);
    } else {
      // 日時不定の場合は常に評価可能
      isExperimentStarted = true;
    }
    
    for (final participantId in _experiment.participants) {
      final userEval = participantEvals[participantId] as Map<String, dynamic>? ?? {};
      final creatorToParticipant = userEval['creatorEvaluated'] ?? false;
      final participantToCreator = userEval['participantEvaluated'] ?? false;
      
      // 実験者がまだ参加者を評価していない場合
      if (!creatorToParticipant) {
        // 実施日時を迎えているか、参加者が既に評価している場合はカウント
        if (isExperimentStarted || participantToCreator) {
          count++;
        }
      }
    }
    
    return count;
  }

  /// 実験を開始する
  Future<void> _startExperiment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('実験を開始しますか？'),
        content: const Text('実験を開始すると、ステータスが「進行中」に変更されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('開始する'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _experimentService.startExperiment(_experiment.id);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('実験を開始しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('実験開始に失敗しました: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 募集を締め切る
  Future<void> _closeRecruitment() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('募集締切'),
        content: const Text('募集を締め切りますか？締切後は新規応募を受け付けません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('締め切る'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('experiments')
            .doc(_experiment.id)
            .update({
          'recruitmentEndDate': DateTime.now().toIso8601String(),
        });

        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('募集を締め切りました'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('募集締切に失敗しました: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// 参加者への一括メッセージ送信
  Future<void> _sendBulkMessage() async {
    // 参加者がいない場合は終了
    if (_participants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('参加者がいません'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final messageController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('参加者への一括メッセージ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_participants.length}名の参加者全員にメッセージを送信します'),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'メッセージを入力...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8E1728),
            ),
            child: const Text('送信'),
          ),
        ],
      ),
    );

    if (result == true && messageController.text.isNotEmpty) {
      // 送信中のダイアログを表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('メッセージを送信中...'),
            ],
          ),
        ),
      );

      int successCount = 0;
      int failureCount = 0;
      final List<String> failedParticipants = [];

      // 現在のユーザー情報を取得
      final currentUser = _currentUser;
      if (currentUser == null) {
        if (mounted) {
          Navigator.pop(context); // 送信中ダイアログを閉じる
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ユーザー情報の取得に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 各参加者にメッセージを送信
      for (final participant in _participants) {
        try {
          // 実験に関するメッセージとして送信
          final message = '【実験: ${_experiment.title}】\n${messageController.text}';

          await _messageService.sendMessage(
            senderId: currentUser.uid,
            receiverId: participant.uid,
            content: message,
            senderName: currentUser.name,
            receiverName: participant.name,
          );
          successCount++;
        } catch (e) {
          failureCount++;
          failedParticipants.add(participant.name);
        }
      }

      // 送信中ダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
      }

      // 結果を表示
      if (mounted) {
        if (failureCount == 0) {
          // 全員に送信成功
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount名全員にメッセージを送信しました'),
              backgroundColor: Colors.green,
            ),
          );
        } else if (successCount == 0) {
          // 全員に送信失敗
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('メッセージの送信に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          // 一部成功、一部失敗
          final failedNames = failedParticipants.join(', ');
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('送信結果'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('✅ 送信成功: $successCount名'),
                  Text('❌ 送信失敗: $failureCount名'),
                  if (failedParticipants.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('送信失敗した参加者:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(failedNames, style: const TextStyle(fontSize: 12)),
                  ],
                ],
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('実験管理'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('実験管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: '実験詳細を表示',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ExperimentDetailScreen(
                    experiment: _experiment,
                    isMyExperiment: true,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.normal,
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: '概要'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('参加者'),
                  if (_getUrlSendableParticipantCount() > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_getUrlSendableParticipantCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  if (_getEvaluatableParticipantCount() > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_getEvaluatableParticipantCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: '設定'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 概要タブ
          _buildOverviewTab(),
          // 参加者タブ
          _buildParticipantsTab(),
          // 設定タブ
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sendBulkMessage,
        backgroundColor: const Color(0xFF8E1728),
        icon: const Icon(Icons.send),
        label: const Text('一括メッセージ'),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final participantCount = _participants.length;
    final maxParticipants = _experiment.maxParticipants ?? 0;
    final completionRate = maxParticipants > 0 
        ? (participantCount / maxParticipants * 100).toInt() 
        : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 実験情報カード
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _experiment.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildStatusBadge(_experiment.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _experiment.description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(
                        Icons.science,
                        _experiment.type.label,
                        _getTypeColor(_experiment.type),
                      ),
                      if (_experiment.isPaid)
                        _buildInfoChip(
                          Icons.payments,
                          '¥${_experiment.reward}',
                          Colors.green,
                        ),
                      if (_experiment.location.isNotEmpty)
                        _buildInfoChip(
                          Icons.location_on,
                          _experiment.location,
                          Colors.blue,
                          isFlexible: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 統計情報
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '参加者数',
                  '$participantCount',
                  subtitle: maxParticipants > 0 ? '/ $maxParticipants名' : null,
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  '充足率',
                  '$completionRate%',
                  icon: Icons.donut_large,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '相互評価未完了',
                  '${_getNotEvaluatedCount()}',
                  icon: Icons.pending_actions,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  '相互評価完了',
                  '${_getEvaluatedCount()}',
                  icon: Icons.check_circle,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // アクションボタン
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'クイックアクション',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 実験開始ボタン（募集中の場合のみ表示）
                      if (_experiment.status == ExperimentStatus.recruiting)
                        ElevatedButton.icon(
                          onPressed: _startExperiment,
                          icon: const Icon(Icons.play_circle_filled),
                          label: const Text('実験を開始'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                        ),
                      if (_experiment.status == ExperimentStatus.recruiting)
                        ElevatedButton.icon(
                          onPressed: _closeRecruitment,
                          icon: const Icon(Icons.block),
                          label: const Text('募集締切'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: _sendBulkMessage,
                        icon: const Icon(Icons.send),
                        label: const Text('参加者にメッセージ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8E1728),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          // TODO: 編集画面への遷移
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('編集機能は実装予定です'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('実験情報を編集'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 日程情報
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '日程情報',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDateInfo('募集開始', _experiment.recruitmentStartDate),
                  const SizedBox(height: 8),
                  _buildDateInfo('募集終了', _experiment.recruitmentEndDate),
                  const SizedBox(height: 8),
                  _buildDateInfo('実験期間開始', _experiment.experimentPeriodStart),
                  const SizedBox(height: 8),
                  _buildDateInfo('実験期間終了', _experiment.experimentPeriodEnd),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // 実験詳細を表示ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExperimentDetailScreen(
                      experiment: _experiment,
                      isMyExperiment: true,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility),
              label: const Text('実験詳細を表示'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8E1728),
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsTab() {
    if (_participants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'まだ参加者がいません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    // 実験が実施日時を迎えているかチェック（評価ボタン表示用）
    bool isExperimentStarted = false;
    
    if (_experiment.allowFlexibleSchedule) {
      // 柔軟なスケジュールの場合（予約制）
      // 実験期間が開始していれば評価可能
      if (_experiment.experimentPeriodStart != null) {
        isExperimentStarted = DateTime.now().isAfter(_experiment.experimentPeriodStart!);
      } else {
        // 期間が設定されていない場合は常に評価可能
        isExperimentStarted = true;
      }
    } else if (_experiment.fixedExperimentDate != null) {
      // 固定日時の場合
      isExperimentStarted = DateTime.now().isAfter(_experiment.fixedExperimentDate!);
    } else {
      // 日時不定の場合は常に評価可能
      isExperimentStarted = true;
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _participants.length,
      itemBuilder: (context, index) {
        final participant = _participants[index];
        
        // participantEvaluationsから個別の評価状態を取得
        final experimentData = _experiment.toFirestore();
        final participantEvals = experimentData['participantEvaluations'] as Map<String, dynamic>? ?? {};
        final userEval = participantEvals[participant.uid] as Map<String, dynamic>? ?? {};
        
        // 実験者から参加者への評価状態
        final creatorToParticipant = userEval['creatorEvaluated'] ?? false;
        // 参加者から実験者への評価状態
        final participantToCreator = userEval['participantEvaluated'] ?? false;
        // 相互評価完了フラグ
        final mutuallyCompleted = userEval['mutuallyCompleted'] ?? false;
        
        // 評価ステータスを判定
        String evaluationStatus;
        Color statusColor;
        IconData statusIcon;
        
        if (mutuallyCompleted) {
          evaluationStatus = '相互評価完了';
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
        } else if (creatorToParticipant && !participantToCreator) {
          evaluationStatus = '相手の評価待ち';
          statusColor = Colors.blue;
          statusIcon = Icons.hourglass_empty;
        } else if (!creatorToParticipant && participantToCreator) {
          evaluationStatus = 'あなたの評価待ち';
          statusColor = Colors.orange;
          statusIcon = Icons.rate_review;
        } else {
          evaluationStatus = '実験実施待ち';
          statusColor = Colors.grey;
          statusIcon = Icons.schedule;
        }
        
        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CustomCircleAvatar(
              frameId: participant.selectedFrame,
              radius: 20,
              backgroundColor: const Color(0xFF8E1728),
              designBuilder: participant.selectedDesign != null && participant.selectedDesign != 'default'
                  ? AvatarDesigns.getById(participant.selectedDesign!).builder
                  : null,
              child: participant.selectedDesign == null || participant.selectedDesign == 'default'
                  ? Text(
                      participant.name.isNotEmpty 
                        ? participant.name[0].toUpperCase() 
                        : '?',
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        evaluationStatus,
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    participant.email,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (participant.department?.isNotEmpty ?? false)
                    Text(
                      '${participant.department} ${participant.grade ?? ""}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // タグ表示エリア
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      // 未評価タグ
                      if (!creatorToParticipant && (isExperimentStarted || participantToCreator))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: const Text(
                            '未評価',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      // 事後アンケート未送信タグ
                      if (_experiment.postSurveyUrl != null &&
                          _experiment.postSurveyUrl!.isNotEmpty &&
                          !_hasPostSurveyUrlSent(participant.uid))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: const Text(
                            '事後アンケート未送信',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Icon(
                              creatorToParticipant ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: creatorToParticipant ? Colors.green : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'あなた→参加者',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            Text(
                              creatorToParticipant ? '評価済' : '未評価',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: creatorToParticipant ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Icon(
                              participantToCreator ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: participantToCreator ? Colors.green : Colors.grey,
                              size: 24,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '参加者→あなた',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            Text(
                              participantToCreator ? '評価済' : '未評価',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: participantToCreator ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        SizedBox(
                          width: MediaQuery.of(context).size.width < 400 ? double.infinity : 150,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatScreen(
                                    otherUserId: participant.uid,
                                    otherUserName: participant.name,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 16),
                            label: const Text('メッセージ'),
                          ),
                        ),
                        // 個別調整の場合、日程設定ボタンを表示
                        if (_experiment.scheduleType == ScheduleType.individual)
                          SizedBox(
                            width: MediaQuery.of(context).size.width < 400 ? double.infinity : 150,
                            child: OutlinedButton.icon(
                              onPressed: () => _showScheduleDialog(participant),
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_getScheduleButtonLabel(participant.uid)),
                            ),
                          ),
                        // 実験者がまだ参加者を評価していない場合、かつ（実施日時を迎えている OR 参加者が既に評価済み）の場合に評価ボタンを表示
                        if (!creatorToParticipant && (isExperimentStarted || participantToCreator))
                          SizedBox(
                            width: MediaQuery.of(context).size.width < 400 ? double.infinity : 150,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ExperimentEvaluationScreen(
                                      experiment: _experiment,
                                      targetUserId: participant.uid,
                                      targetUserName: participant.name,
                                    ),
                                  ),
                                ).then((result) {
                                  if (result == true) {
                                    _loadData(); // 評価完了後にデータを再読み込み
                                  }
                                });
                              },
                              icon: const Icon(Icons.star, size: 16),
                              label: const Text('評価する'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                              ),
                            ),
                          ),
                        // 実験後アンケートURLが設定されている場合、URL送信ボタンを表示
                        if (_experiment.postSurveyUrl != null && _experiment.postSurveyUrl!.isNotEmpty)
                          SizedBox(
                            width: MediaQuery.of(context).size.width < 400 ? double.infinity : 150,
                            child: OutlinedButton.icon(
                              onPressed: () => _sendPostSurveyUrl(participant),
                              icon: Icon(
                                _hasPostSurveyUrlSent(participant.uid)
                                  ? Icons.check_circle
                                  : Icons.send,
                                size: 16,
                                color: _hasPostSurveyUrlSent(participant.uid)
                                  ? Colors.green
                                  : null,
                              ),
                              label: Text(
                                _hasPostSurveyUrlSent(participant.uid)
                                  ? '送信済'
                                  : '事後アンケート送信',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _hasPostSurveyUrlSent(participant.uid)
                                  ? Colors.green
                                  : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '実験設定',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('実験情報を編集'),
                    subtitle: const Text('タイトル、説明、報酬などを変更'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // TODO: 編集画面への遷移
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('編集機能は実装予定です'),
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.notifications),
                    title: const Text('通知設定'),
                    subtitle: const Text('新規応募時の通知など'),
                    trailing: Switch(
                      value: true,
                      onChanged: (value) {
                        // TODO: 通知設定の変更
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      '実験を削除',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: const Text('この操作は取り消せません'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('実験の削除'),
                          content: const Text(
                            'この実験を削除しますか？\nこの操作は取り消せません。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('キャンセル'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('削除'),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        // TODO: 削除処理
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('削除機能は実装予定です'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 実験タイプ別の設定
          if (_experiment.type == ExperimentType.survey)
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'アンケート設定',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: const Text('アンケートURL'),
                      subtitle: Text(
                        _experiment.surveyUrl ?? 'URLが設定されていません',
                        style: TextStyle(
                          color: _experiment.surveyUrl != null 
                              ? Colors.blue 
                              : Colors.grey,
                        ),
                      ),
                      trailing: const Icon(Icons.edit, size: 20),
                      onTap: () {
                        // TODO: URL編集ダイアログ
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('URL編集機能は実装予定です'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value, {
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color, {bool isFlexible = false}) {
    return Container(
      constraints: isFlexible 
        ? const BoxConstraints(maxWidth: 200) 
        : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ExperimentStatus status) {
    Color color;
    switch (status) {
      case ExperimentStatus.recruiting:
        color = const Color(0xFF8E1728);
        break;
      case ExperimentStatus.ongoing:
        color = Colors.blue;
        break;
      case ExperimentStatus.waitingEvaluation:
        color = Colors.orange;
        break;
      case ExperimentStatus.completed:
        color = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDateInfo(String label, DateTime? date) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          date != null 
              ? DateFormat('yyyy/MM/dd HH:mm').format(date)
              : '未設定',
          style: TextStyle(
            fontSize: 14,
            fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
            color: date != null ? Colors.black : Colors.grey,
          ),
        ),
      ],
    );
  }

  /// 日程設定ボタンのラベルを取得
  String _getScheduleButtonLabel(String participantId) {
    final participantSchedule = _experiment.participantEvaluations?[participantId];
    if (participantSchedule != null && participantSchedule['scheduledDate'] != null) {
      final date = (participantSchedule['scheduledDate'] as Timestamp).toDate();
      return DateFormat('MM/dd HH:mm').format(date);
    }
    return '日程設定';
  }
  
  /// 日程設定ダイアログを表示
  Future<void> _showScheduleDialog(AppUser participant) async {
    final participantSchedule = _experiment.participantEvaluations?[participant.uid];
    DateTime? currentDate;
    TimeOfDay? currentTime;
    String? location;
    
    if (participantSchedule != null && participantSchedule['scheduledDate'] != null) {
      final scheduledDate = (participantSchedule['scheduledDate'] as Timestamp).toDate();
      currentDate = scheduledDate;
      currentTime = TimeOfDay.fromDateTime(scheduledDate);
      location = participantSchedule['location'];
    }
    
    await showDialog(
      context: context,
      builder: (context) => _ScheduleSettingDialog(
        participant: participant,
        experiment: _experiment,
        initialDate: currentDate,
        initialTime: currentTime,
        initialLocation: location,
        onScheduleSet: (date, time, loc) async {
          final scheduledDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
          
          setState(() => _isLoading = true);
          
          try {
            await _scheduleService.setParticipantSchedule(
              experimentId: _experiment.id,
              participantId: participant.uid,
              scheduledDate: scheduledDateTime,
              location: loc,
            );
            
            await _loadData();
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('日程を設定しました。カレンダーに自動登録されました。'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('日程設定に失敗しました: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } finally {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          }
        },
      ),
    );
  }
  
  Color _getTypeColor(ExperimentType type) {
    switch (type) {
      case ExperimentType.online:
        return Colors.blue;
      case ExperimentType.onsite:
        return Colors.orange;
      case ExperimentType.survey:
        return Colors.green;
    }
  }

  int _getNotEvaluatedCount() {
    // 相互評価が未完了の参加者数
    int count = 0;
    for (final participantId in _experiment.participants) {
      if (!_experiment.isMutuallyCompletedWithUser(participantId)) {
        count++;
      }
    }
    return count;
  }

  int _getEvaluatedCount() {
    // 相互評価が完了している参加者数
    int count = 0;
    for (final participantId in _experiment.participants) {
      if (_experiment.isMutuallyCompletedWithUser(participantId)) {
        count++;
      }
    }
    return count;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

/// 日程設定ダイアログ
class _ScheduleSettingDialog extends StatefulWidget {
  final AppUser participant;
  final Experiment experiment;
  final DateTime? initialDate;
  final TimeOfDay? initialTime;
  final String? initialLocation;
  final Function(DateTime, TimeOfDay, String?) onScheduleSet;
  
  const _ScheduleSettingDialog({
    required this.participant,
    required this.experiment,
    this.initialDate,
    this.initialTime,
    this.initialLocation,
    required this.onScheduleSet,
  });
  
  @override
  State<_ScheduleSettingDialog> createState() => _ScheduleSettingDialogState();
}

class _ScheduleSettingDialogState extends State<_ScheduleSettingDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  final TextEditingController _locationController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _selectedTime = widget.initialTime ?? TimeOfDay.now();
    _locationController.text = widget.initialLocation ?? widget.experiment.location;
  }
  
  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }
  
  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }
  
  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    
    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.participant.name}さんの実験日程設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '実験実施日時',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('yyyy/MM/dd').format(_selectedDate)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(_selectedTime.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '場所（オプション）',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                hintText: widget.experiment.type == ExperimentType.online 
                  ? 'オンライン会議のURL等' 
                  : '実施場所',
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '設定すると、参加者に通知が送信され、双方のGoogleカレンダーに自動登録されます',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onScheduleSet(
              _selectedDate,
              _selectedTime,
              _locationController.text.isNotEmpty ? _locationController.text : null,
            );
            Navigator.pop(context);
          },
          child: const Text('設定'),
        ),
      ],
    );
  }
}