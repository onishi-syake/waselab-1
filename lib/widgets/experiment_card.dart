import 'package:flutter/material.dart';
import '../models/experiment.dart';
import '../models/app_user.dart';
import '../services/user_cache_service.dart';
import '../screens/experiment_detail_screen.dart';
import '../screens/experiment_detail_screen_demo.dart';

/// 実験カードの共通ウィジェット
class ExperimentCard extends StatefulWidget {
  final Experiment experiment;
  final bool isDemo;
  final String? currentUserId;
  
  const ExperimentCard({
    super.key,
    required this.experiment,
    this.isDemo = false,
    this.currentUserId,
  });

  @override
  State<ExperimentCard> createState() => _ExperimentCardState();
}

class _ExperimentCardState extends State<ExperimentCard> {
  final UserCacheService _userCache = UserCacheService();
  AppUser? _creator;
  bool _isLoadingCreator = true;

  @override
  void initState() {
    super.initState();
    _loadCreator();
  }

  @override
  void didUpdateWidget(ExperimentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.experiment.creatorId != widget.experiment.creatorId) {
      _isLoadingCreator = true;
      _loadCreator();
    }
  }

  Future<void> _loadCreator() async {
    final creator = await _userCache.getUserById(widget.experiment.creatorId);
    if (mounted) {
      setState(() {
        _creator = creator;
        _isLoadingCreator = false;
      });
    }
  }

  /// 実験種別のアイコンを取得
  IconData _getTypeIcon(ExperimentType type) {
    switch (type) {
      case ExperimentType.online:
        return Icons.computer;
      case ExperimentType.onsite:
        return Icons.location_on;
      case ExperimentType.survey:
        return Icons.assignment;
    }
  }

  /// 実験種別の色を取得
  Color _getTypeColor(ExperimentType type) {
    switch (type) {
      case ExperimentType.online:
        return const Color(0xFF2E7D32); // 緑
      case ExperimentType.onsite:
        return const Color(0xFF1976D2); // 青
      case ExperimentType.survey:
        return const Color(0xFFE65100); // オレンジ
    }
  }

  @override
  Widget build(BuildContext context) {
    // 締切までの残り日数を計算
    final daysLeft = widget.experiment.endDate?.difference(DateTime.now()).inDays;

    // 実験の状態判定
    final now = DateTime.now();
    final userId = widget.currentUserId ?? '';

    // 募集終了判定（募集期限が過ぎているか、ステータスが募集中以外）
    final isRecruitmentEnded = (widget.experiment.recruitmentEndDate != null &&
                                widget.experiment.recruitmentEndDate!.isBefore(now)) ||
                               widget.experiment.status != ExperimentStatus.recruiting;

    // 実験完了判定
    final isCompleted = widget.experiment.status == ExperimentStatus.completed ||
                       (userId.isNotEmpty &&
                        widget.experiment.participants.contains(userId) &&
                        widget.experiment.isCompletedForParticipant(userId));

    // 評価待ち判定
    final isWaitingEvaluation = userId.isNotEmpty &&
                                widget.experiment.isWaitingForEvaluation(userId) &&
                                !isCompleted;

    // 満員判定（募集中の場合のみ）
    final isFull = !isRecruitmentEnded &&
                  widget.experiment.status == ExperimentStatus.recruiting &&
                  widget.experiment.maxParticipants != null &&
                  widget.experiment.participants.length >= widget.experiment.maxParticipants!;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8E1728).withValues(alpha: 0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => widget.isDemo
                  ? ExperimentDetailScreenDemo(experiment: widget.experiment)
                  : ExperimentDetailScreen(experiment: widget.experiment),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 260, // 固定高さでレイアウトを制約
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // 締切タグとスケジュールタイプ表示、状態バッジ
              Row(
                children: [
                  // 完了済みタグ（最優先表示）
                  if (isCompleted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '完了済み',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  // 評価待ちタグ
                  else if (isWaitingEvaluation)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.rate_review,
                            size: 12,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '評価待ち',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  // 募集終了タグ
                  else if (isRecruitmentEnded)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block,
                            size: 12,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '募集終了',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  // 満員タグ（募集終了でない場合に表示）
                  else if (isFull)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.people_alt,
                            size: 12,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '満員',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 状態バッジ（自分の実験または参加予定）
                  if (!isRecruitmentEnded && !isCompleted && !isFull && widget.currentUserId != null && widget.experiment.creatorId == widget.currentUserId)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8E1728).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF8E1728).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.campaign,
                            size: 12,
                            color: Color(0xFF8E1728),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '募集中',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8E1728),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!isRecruitmentEnded && !isCompleted && !isFull && widget.currentUserId != null &&
                      widget.experiment.participants.contains(widget.currentUserId))
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: Colors.blue[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '参加予定',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // 柔軟なスケジュール調整のバッジ
                  if (!isRecruitmentEnded && !isCompleted && widget.experiment.allowFlexibleSchedule)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month,
                            size: 12,
                            color: Colors.blue[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '日程調整可',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isRecruitmentEnded && !isCompleted && widget.experiment.type == ExperimentType.survey)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 12,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '日時自由',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isRecruitmentEnded && !isCompleted && widget.experiment.fixedExperimentDate != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.purple.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event,
                            size: 12,
                            color: Colors.purple[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '日時固定',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple[700],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!isRecruitmentEnded && !isCompleted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 12,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '日時未定',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  // アンケートバッジ
                  if (widget.experiment.preSurveyUrl != null ||
                      widget.experiment.postSurveyUrl != null ||
                      (widget.experiment.surveyUrl != null && widget.experiment.type == ExperimentType.survey)) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 実験前アンケート
                        if (widget.experiment.preSurveyUrl != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6, right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.purple.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fact_check,
                                  size: 10,
                                  color: Colors.purple[700],
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '前',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // 実験後アンケート
                        if (widget.experiment.postSurveyUrl != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6, right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.indigo.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.quiz,
                                  size: 10,
                                  color: Colors.indigo[700],
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '後',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  // 締切タグ
                  if (daysLeft != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: daysLeft <= 3
                          ? Colors.red.withValues(alpha: 0.1)
                          : daysLeft <= 7
                            ? Colors.orange.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        daysLeft <= 0
                          ? '本日締切'
                          : daysLeft == 1
                            ? '明日締切'
                            : 'あと$daysLeft日',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: daysLeft <= 3
                            ? Colors.red[700]
                            : daysLeft <= 7
                              ? Colors.orange[700]
                              : Colors.green[700],
                        ),
                      ),
                    ),
                ],
              ),
              
              // タイトルと研究室名
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.experiment.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C2C2C),
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.school,
                        size: 14,
                        color: Color(0xFF8E1728),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.experiment.labName ?? "研究室名未設定"} / ${_isLoadingCreator ? '読み込み中...' : (_creator?.name ?? '不明')}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF8E1728),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 6),
              
              // 説明文
              Text(
                widget.experiment.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey[700],
                  height: 1.3,
                  letterSpacing: 0.05,
                ),
              ),
              
              // スペースを埋めて情報を下部に配置
              Expanded(child: Container()),
              
              // 情報グリッド
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // 報酬（最重要）
                    Icon(
                      Icons.payments_outlined,
                      size: 16,
                      color: widget.experiment.isPaid ? const Color(0xFF8E1728) : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.experiment.isPaid 
                        ? '¥${widget.experiment.reward.toString().replaceAllMapped(
                            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                            (Match m) => '${m[1]},',
                          )}'
                        : '無償',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.experiment.isPaid ? const Color(0xFF8E1728) : Colors.grey[700],
                      ),
                    ),
                    // 所要時間（2番目）
                    if (widget.experiment.duration != null) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 1,
                        height: 24,
                        child: ColoredBox(color: Color(0xFFE0E0E0)),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.timer_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.experiment.duration}分',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                    // カテゴリ（3番目）
                    const SizedBox(width: 6),
                    Container(
                      width: 1,
                      height: 24,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getTypeIcon(widget.experiment.type),
                            size: 16,
                            color: _getTypeColor(widget.experiment.type),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.experiment.type.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _getTypeColor(widget.experiment.type),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 募集人数（最後）
                    if (widget.experiment.maxParticipants != null) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 1,
                        height: 20,
                        child: ColoredBox(color: Color(0xFFE0E0E0)),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.group_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '募集${widget.experiment.maxParticipants}名',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 2),
              
              // 場所情報と日程情報
              Row(
                children: [
                  // 場所情報
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.experiment.location,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[900],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 日程情報
                  if (widget.experiment.allowFlexibleSchedule)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.date_range, size: 16, color: Colors.green[700]),
                          const SizedBox(width: 4),
                          Text(
                            '予約制',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[900],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}