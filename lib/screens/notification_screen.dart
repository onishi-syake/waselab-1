import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/notification.dart';
import '../models/experiment.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/experiment_service.dart';
import '../services/google_calendar_service.dart';
import '../services/reservation_service.dart';
import '../services/flexible_schedule_service.dart';
import 'messages_screen.dart';
import 'experiment_detail_screen.dart';
import 'experiment_management_screen.dart';
import 'evaluation_history_screen.dart';
import 'support_chat_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();
  final ExperimentService _experimentService = ExperimentService();
  final GoogleCalendarService _calendarService = GoogleCalendarService();
  final ReservationService _reservationService = ReservationService();
  final FlexibleScheduleService _scheduleService = FlexibleScheduleService();
  String? _currentUserId;
  final Set<String> _addingToCalendar = {};
  
  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }
  
  Future<void> _loadCurrentUser() async {
    final user = _authService.currentUser;
    if (user != null) {
      setState(() {
        _currentUserId = user.uid;
      });
      // 古い通知を削除
      await _notificationService.deleteOldNotifications(user.uid);
    }
  }

  Future<void> _handleNotificationTap(AppNotification notification) async {
    // 通知を既読にする
    await _notificationService.markAsRead(notification.id);
    
    if (!mounted) return;
    
    // 通知タイプに応じて画面遷移
    switch (notification.type) {
      case NotificationType.evaluation:
        // 評価履歴画面に遷移
        if (notification.data?['experimentId'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EvaluationHistoryScreen(
                userId: _currentUserId!,
                userName: '',
                isMyHistory: true,
              ),
            ),
          );
        }
        break;
        
      case NotificationType.message:
        // メッセージ画面に遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const MessagesScreen(),
          ),
        );
        break;
        
      case NotificationType.experimentJoined:
      case NotificationType.experimentCancelled:
      case NotificationType.experimentCompleted:
      case NotificationType.experimentStarted:
        // 実験詳細または管理画面に遷移
        if (notification.data?['experimentId'] != null) {
          try {
            final experiment = await _experimentService.getExperiment(
              notification.data!['experimentId'],
            );
            if (experiment != null && mounted) {
              if (experiment.creatorId == _currentUserId) {
                // 自分が作成した実験なら管理画面へ
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExperimentManagementScreen(
                      experiment: experiment,
                    ),
                  ),
                );
              } else {
                // 参加した実験なら詳細画面へ
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ExperimentDetailScreen(
                      experiment: experiment,
                      isMyExperiment: false,
                    ),
                  ),
                );
              }
            }
          } catch (e) {
          }
        }
        break;
        
      case NotificationType.adminMessage:
        // 運営からのお知らせはダイアログで表示
        _showAdminMessageDialog(notification);
        break;
        
      case NotificationType.supportTicket:
      case NotificationType.supportReply:
        // サポートチャット画面に遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SupportChatScreen(),
          ),
        );
        break;

      case NotificationType.preSurveyAvailable:
        // 事前アンケートURLの処理
        if (notification.data?['surveyUrl'] != null) {
          _showPostSurveyUrlDialog(notification);
        }
        break;

      case NotificationType.postSurveyUrl:
        // 実験後アンケートURLの処理
        if (notification.data?['surveyUrl'] != null) {
          _showPostSurveyUrlDialog(notification);
        }
        break;
    }
  }

  void _showPostSurveyUrlDialog(AppNotification notification) {
    final surveyUrl = notification.data?['surveyUrl'] as String?;
    final experimentTitle = notification.data?['experimentTitle'] as String? ?? '実験';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.assignment,
              color: Colors.blue[700],
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '実験後アンケート',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「$experimentTitle」の実験後アンケートが届きました。'),
            const SizedBox(height: 16),
            if (surveyUrl != null) ...[
              const Text(
                'アンケートURL:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse(surveyUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URLを開けませんでした'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: Text(
                  surveyUrl,
                  style: TextStyle(
                    color: Colors.blue[700],
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          if (surveyUrl != null)
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(surveyUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('アンケートを開く'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
              ),
            ),
        ],
      ),
    );
  }
  
  void _showAdminMessageDialog(AppNotification notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.campaign,
              color: Colors.red[700],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                notification.title,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(notification.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
  
  // カレンダー追加が可能かチェック
  Future<bool> _canAddToCalendar(AppNotification notification) async {
    try {
      final experimentId = notification.data?['experimentId'];
      if (experimentId == null) {
        debugPrint('[Calendar] No experimentId in notification');
        return false;
      }

      final experiment = await _experimentService.getExperiment(experimentId);
      if (experiment == null) {
        debugPrint('[Calendar] Experiment not found: $experimentId');
        return false;
      }

      // デバッグ: 通知データをログ出力
      debugPrint('[Calendar] Notification data: ${notification.data}');
      debugPrint('[Calendar] Experiment type: ${experiment.scheduleType}');
      debugPrint('[Calendar] Is participant notification: ${notification.data?['isParticipantNotification']}');

      // 日程確定通知の場合は追加可能
      if (notification.data?['scheduledDate'] != null) {
        debugPrint('[Calendar] Has scheduledDate - can add');
        return true;
      }

      // 参加者側の通知の場合
      if (notification.data?['isParticipantNotification'] == true) {
        // 固定日時の実験は追加可能
        if (experiment.fixedExperimentDate != null) {
          debugPrint('[Calendar] Fixed date experiment - can add');
          return true;
        }
        // 予約制の実験でスロット情報（日時情報）がある場合は追加可能
        if (experiment.scheduleType == ScheduleType.reservation) {
          final hasSlotId = notification.data?['slotId'] != null;
          final hasStartTime = notification.data?['startTime'] != null;
          debugPrint('[Calendar] Reservation experiment - slotId: $hasSlotId, startTime: $hasStartTime');
          if (hasSlotId || hasStartTime) {
            debugPrint('[Calendar] Has slot info - can add');
            return true;
          }
        }
        // 個別調整の実驗は日程が決まるまで追加不可
        if (experiment.scheduleType == ScheduleType.individual) {
          debugPrint('[Calendar] Individual schedule - cannot add');
          return false;
        }
      }

      // 実験者側の通知の場合
      if (notification.data?['participantName'] != null) {
        debugPrint('[Calendar] Creator notification detected');
        // スロットIDがある場合（予約制）は追加可能
        if (notification.data?['slotId'] != null) {
          debugPrint('[Calendar] Creator: Has slotId - can add');
          return true;
        }
        // 固定日時の実験は追加可能
        if (experiment.fixedExperimentDate != null) {
          debugPrint('[Calendar] Creator: Fixed date - can add');
          return true;
        }
        // 個別調整の場合は日程確定通知で追加可能
        if (experiment.scheduleType == ScheduleType.individual &&
            notification.data?['scheduledDate'] != null) {
          debugPrint('[Calendar] Creator: Individual with scheduled date - can add');
          return true;
        }
      }

      debugPrint('[Calendar] No conditions met - cannot add');
      return false;
    } catch (e) {
      debugPrint('[Calendar] Error in _canAddToCalendar: $e');
      return false;
    }
  }

  Future<void> _addToCalendar(AppNotification notification) async {
    // カレンダー連携が有効かチェック
    if (!await _calendarService.isCalendarEnabled()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('設定画面でGoogleカレンダー連携を有効にしてください'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _addingToCalendar.add(notification.id);
    });

    try {
      // 通知データから情報を取得
      final experimentId = notification.data?['experimentId'];
      final slotId = notification.data?['slotId'];
      final participantName = notification.data?['participantName'] ?? 'ユーザー';

      if (experimentId == null) {
        throw Exception('実験情報が見つかりません');
      }

      // 実験情報を取得
      final experiment = await _experimentService.getExperiment(experimentId);
      if (experiment == null) {
        throw Exception('実験が見つかりません');
      }
      
      // 参加者側の通知の場合（「実験に参加しました」通知）
      if (notification.data?['isParticipantNotification'] == true) {
        // 日時の種類を判定
        DateTime? startTime;
        DateTime? endTime;

        // 予約制の実験でスロット情報がある場合
        if (experiment.scheduleType == ScheduleType.reservation) {
          // startTimeがある場合はそれを使用
          if (notification.data?['startTime'] != null) {
            startTime = DateTime.parse(notification.data!['startTime']);
            endTime = DateTime.parse(notification.data!['endTime']);
          }
          // slotIdしかない場合は動的に取得
          else if (notification.data?['slotId'] != null) {
            try {
              final slot = await _reservationService.getSlotById(notification.data!['slotId']);
              startTime = slot.startTime;
              endTime = slot.endTime;
              debugPrint('[Calendar] Fetched slot times - start: $startTime, end: $endTime');
            } catch (e) {
              debugPrint('[Calendar] Failed to fetch slot info: $e');
            }
          }

          if (startTime != null && endTime != null) {
            // 参加者用カレンダーイベントを追加
            final eventId = await _calendarService.addParticipantExperimentToCalendar(
              experimentTitle: experiment.title,
              startTime: startTime,
              endTime: endTime,
              location: experiment.location,
              surveyUrl: experiment.surveyUrl,
              preSurveyUrl: experiment.preSurveyUrl,
              type: experiment.type,
            );

            if (eventId != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Googleカレンダーに予定を追加しました'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        }
        // 固定日時の実験
        else if (experiment.fixedExperimentDate != null) {
          startTime = experiment.fixedExperimentDate!;

          if (experiment.fixedExperimentTime != null) {
            final hour = experiment.fixedExperimentTime!['hour'] ?? 0;
            final minute = experiment.fixedExperimentTime!['minute'] ?? 0;
            startTime = DateTime(
              startTime.year,
              startTime.month,
              startTime.day,
              hour,
              minute,
            );
          }
          endTime = startTime.add(Duration(minutes: experiment.duration ?? 60));

          // 参加者用カレンダーイベントを追加
          final eventId = await _calendarService.addParticipantExperimentToCalendar(
            experimentTitle: experiment.title,
            startTime: startTime,
            endTime: endTime,
            location: experiment.location,
            surveyUrl: experiment.surveyUrl,
            preSurveyUrl: experiment.preSurveyUrl,
            type: experiment.type,
          );

          if (eventId != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Googleカレンダーに予定を追加しました'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
        // 個別調整の実験
        else if (experiment.scheduleType == ScheduleType.individual) {
          // 柔軟な日程の場合は後で日程が確定したら追加できるようにメッセージを表示
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('日程が確定したら通知からカレンダーに追加できます'),
                backgroundColor: Colors.blue,
              ),
            );
          }
        } else {
          throw Exception('日時が確定していない実験です');
        }
        return;
      }

      // 日程確定通知の場合（柔軟な日程調整）
      if (notification.data?['scheduledDate'] != null) {
        final scheduledDate = DateTime.parse(notification.data!['scheduledDate']);
        final endTime = scheduledDate.add(Duration(minutes: experiment.duration ?? 60));

        // 実験者側の通知の場合
        if (notification.data?['isCreatorNotification'] == true) {
          final participantName = notification.data?['participantName'] ?? '参加者';

          // 実験者側のカレンダーに追加
          final eventId = await _calendarService.quickAddReservationToCalendar(
            experimentTitle: experiment.title,
            startTime: scheduledDate,
            endTime: endTime,
            participantName: participantName,
            location: experiment.location,
            surveyUrl: experiment.surveyUrl,
            type: experiment.type,
          );

          if (eventId != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Googleカレンダーに予定を追加しました'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // 参加者側からカレンダーに追加
          final eventId = await _scheduleService.addParticipantCalendarEvent(
            experimentId: experimentId,
            participantId: _currentUserId!,
          );

          if (eventId != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Googleカレンダーに予定を追加しました'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
        return;
      }
      
      // スロット情報がある場合は取得
      if (slotId != null) {
        final slot = await _reservationService.getSlotById(slotId);
        
        // クイック追加（実験作成者用）
        final eventId = await _calendarService.quickAddReservationToCalendar(
          experimentTitle: experiment.title,
          startTime: slot.startTime,
          endTime: slot.endTime,
          participantName: participantName,
          location: experiment.location,
          surveyUrl: experiment.surveyUrl,
          type: experiment.type,
        );
        
        if (eventId != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Googleカレンダーに予定を追加しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (experiment.fixedExperimentDate != null) {
        // 固定日時の実験の場合
        DateTime startTime = experiment.fixedExperimentDate!;
        DateTime endTime = startTime;
        
        if (experiment.fixedExperimentTime != null) {
          final hour = experiment.fixedExperimentTime!['hour'] ?? 0;
          final minute = experiment.fixedExperimentTime!['minute'] ?? 0;
          startTime = DateTime(
            startTime.year,
            startTime.month,
            startTime.day,
            hour,
            minute,
          );
          endTime = startTime.add(Duration(minutes: experiment.duration ?? 60));
        } else {
          endTime = startTime.add(Duration(minutes: experiment.duration ?? 60));
        }
        
        final eventId = await _calendarService.quickAddReservationToCalendar(
          experimentTitle: experiment.title,
          startTime: startTime,
          endTime: endTime,
          participantName: participantName,
          location: experiment.location,
          surveyUrl: experiment.surveyUrl,
          type: experiment.type,
        );
        
        if (eventId != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Googleカレンダーに予定を追加しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('日時が確定していない実験です');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カレンダー追加に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingToCalendar.remove(notification.id);
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    if (_currentUserId != null) {
      await _notificationService.markAllAsRead(_currentUserId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('すべての通知を既読にしました'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 1) {
      return 'たった今';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}時間前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}日前';
    } else {
      return DateFormat('yyyy/MM/dd').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('通知'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'すべて既読にする',
            onPressed: _markAllAsRead,
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationService.getUserNotifications(_currentUserId!),
        builder: (context, snapshot) {
          // エラーチェックを追加
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '通知の取得に失敗しました',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '通知はありません',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }
          
          final notifications = snapshot.data!;
          
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final isUnread = !notification.isRead;
              
              return Dismissible(
                key: Key(notification.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                onDismissed: (_) async {
                  await _notificationService.deleteNotification(notification.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('通知を削除しました'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: isUnread ? null : Colors.grey.withValues(alpha: 0.05),
                  child: InkWell(
                    onTap: () => _handleNotificationTap(notification),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _getNotificationColor(notification.type)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              notification.type.icon,
                              color: _getNotificationColor(notification.type),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (isUnread)
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        notification.title,
                                        style: TextStyle(
                                          fontWeight: isUnread
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _formatDate(notification.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  notification.message,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[800],
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      notification.type.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: _getNotificationColor(notification.type),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    // 実験参加通知または日程確定通知の場合はカレンダー追加ボタンを表示
                                    // ただし、日時が未定の実験は除外
                                    if (notification.type == NotificationType.experimentJoined &&
                                        notification.data?['experimentId'] != null)
                                      FutureBuilder<bool>(
                                        future: _canAddToCalendar(notification),
                                        builder: (context, snapshot) {
                                          if (!snapshot.hasData || !snapshot.data!) {
                                            return const SizedBox.shrink();
                                          }

                                          return _addingToCalendar.contains(notification.id)
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () => _addToCalendar(notification),
                                                  borderRadius: BorderRadius.circular(4),
                                                  splashColor: Colors.blue.withOpacity(0.3),
                                                  highlightColor: Colors.blue.withOpacity(0.1),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.withOpacity(0.1),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: Colors.blue.withOpacity(0.3),
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: const Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.calendar_today,
                                                          size: 14,
                                                          color: Colors.blue,
                                                        ),
                                                        SizedBox(width: 3),
                                                        Text(
                                                          '日程を追加',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.blue,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
  
  Color _getNotificationColor(NotificationType type) {
    switch (type) {
      case NotificationType.evaluation:
        return Colors.orange;
      case NotificationType.message:
        return Colors.blue;
      case NotificationType.experimentJoined:
        return Colors.green;
      case NotificationType.experimentCancelled:
        return Colors.red;
      case NotificationType.experimentCompleted:
        return Colors.purple;
      case NotificationType.experimentStarted:
        return Colors.green[700]!;
      case NotificationType.adminMessage:
        return Colors.red[700]!;
      case NotificationType.supportTicket:
        return Colors.indigo;
      case NotificationType.supportReply:
        return Colors.teal;
      case NotificationType.preSurveyAvailable:
        return Colors.indigo[600]!;
      case NotificationType.postSurveyUrl:
        return Colors.blue[700]!;
    }
  }
}