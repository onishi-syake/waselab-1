import 'package:cloud_firestore/cloud_firestore.dart';
import 'experiment.dart';
import 'experiment_slot.dart';

/// 予約状態
enum ReservationStatus {
  pending('確認中'),
  confirmed('確定'),
  cancelled('キャンセル'),
  completed('完了');

  final String label;
  const ReservationStatus(this.label);
}

/// 実験予約のモデル
class ExperimentReservation {
  final String id;
  final String userId;           // 予約者のユーザーID
  final String experimentId;     // 実験ID
  final String slotId;          // 予約枠ID
  final DateTime reservedAt;     // 予約日時
  final ReservationStatus status; // 予約状態
  final String? cancelReason;    // キャンセル理由（オプション）
  final String? note;           // 備考（オプション）
  final String? googleCalendarEventId; // GoogleカレンダーイベントID（オプション）
  final DateTime? calendarSyncedAt;    // カレンダー同期日時（オプション）

  ExperimentReservation({
    required this.id,
    required this.userId,
    required this.experimentId,
    required this.slotId,
    required this.reservedAt,
    required this.status,
    this.cancelReason,
    this.note,
    this.googleCalendarEventId,
    this.calendarSyncedAt,
  });

  /// FirestoreのドキュメントからExperimentReservationを作成
  factory ExperimentReservation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return ExperimentReservation(
      id: doc.id,
      userId: data['userId'] ?? '',
      experimentId: data['experimentId'] ?? '',
      slotId: data['slotId'] ?? '',
      reservedAt: (data['reservedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: ReservationStatus.values.firstWhere(
        (e) => e.name == (data['status'] ?? 'pending'),
        orElse: () => ReservationStatus.pending,
      ),
      cancelReason: data['cancelReason'],
      note: data['note'],
      googleCalendarEventId: data['googleCalendarEventId'],
      calendarSyncedAt: (data['calendarSyncedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// ExperimentReservationをFirestoreに保存する形式に変換
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'experimentId': experimentId,
      'slotId': slotId,
      'reservedAt': Timestamp.fromDate(reservedAt),
      'status': status.name,
      'cancelReason': cancelReason,
      'note': note,
      if (googleCalendarEventId != null) 'googleCalendarEventId': googleCalendarEventId,
      if (calendarSyncedAt != null) 'calendarSyncedAt': Timestamp.fromDate(calendarSyncedAt!),
    };
  }

  /// コピーを作成（一部のフィールドを更新）
  ExperimentReservation copyWith({
    String? id,
    String? userId,
    String? experimentId,
    String? slotId,
    DateTime? reservedAt,
    ReservationStatus? status,
    String? cancelReason,
    String? note,
    String? googleCalendarEventId,
    DateTime? calendarSyncedAt,
  }) {
    return ExperimentReservation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      experimentId: experimentId ?? this.experimentId,
      slotId: slotId ?? this.slotId,
      reservedAt: reservedAt ?? this.reservedAt,
      status: status ?? this.status,
      cancelReason: cancelReason ?? this.cancelReason,
      note: note ?? this.note,
      googleCalendarEventId: googleCalendarEventId ?? this.googleCalendarEventId,
      calendarSyncedAt: calendarSyncedAt ?? this.calendarSyncedAt,
    );
  }

  /// キャンセル可能かどうかを判定
  /// @param experiment 実験情報
  /// @param slot 予約枠情報（オプション）
  bool canCancel(Experiment experiment, {ExperimentSlot? slot}) {
    // 既にキャンセル済みまたは完了済みの場合はキャンセル不可
    if (status == ReservationStatus.cancelled || status == ReservationStatus.completed) {
      return false;
    }

    // 実験がアンケート型の場合は常にキャンセル可能
    if (experiment.type == ExperimentType.survey) {
      return true;
    }

    // 固定日時の実験の場合
    if (experiment.fixedExperimentDate != null) {
      final now = DateTime.now();
      final experimentDate = experiment.fixedExperimentDate!;

      // 時刻情報がある場合
      if (experiment.fixedExperimentTime != null) {
        final hour = experiment.fixedExperimentTime!['hour'] ?? 0;
        final minute = experiment.fixedExperimentTime!['minute'] ?? 0;
        final scheduledDateTime = DateTime(
          experimentDate.year,
          experimentDate.month,
          experimentDate.day,
          hour,
          minute,
        );

        // 実施日時の予約締切日数前までキャンセル可能
        final deadline = scheduledDateTime.subtract(Duration(days: experiment.reservationDeadlineDays));
        return now.isBefore(deadline);
      }

      // 日付のみの場合は当日の0:00を基準にする
      final startOfDay = DateTime(
        experimentDate.year,
        experimentDate.month,
        experimentDate.day,
      );
      final deadline = startOfDay.subtract(Duration(days: experiment.reservationDeadlineDays));
      return now.isBefore(deadline);
    }

    // スロット予約の場合（柔軟な日程調整より前に判定）
    if (slot != null) {
      final now = DateTime.now();
      final deadline = slot.startTime.subtract(Duration(days: experiment.reservationDeadlineDays));
      return now.isBefore(deadline);
    }

    // 柔軟な日程調整が可能な実験の場合
    if (experiment.allowFlexibleSchedule) {
      // 参加者の個別スケジュール情報がある場合
      if (experiment.participantEvaluations != null &&
          experiment.participantEvaluations!.containsKey(userId)) {
        final participantInfo = experiment.participantEvaluations![userId];
        if (participantInfo != null && participantInfo['scheduledDate'] != null) {
          final scheduledDate = (participantInfo['scheduledDate'] as Timestamp).toDate();
          final deadline = scheduledDate.subtract(Duration(days: experiment.reservationDeadlineDays));
          return DateTime.now().isBefore(deadline);
        }
      }
      // スケジュール未確定の場合は常にキャンセル可能
      return true;
    }

    // その他の場合（通常の実験期間がある場合）
    if (experiment.experimentPeriodStart != null) {
      final now = DateTime.now();
      final deadline = experiment.experimentPeriodStart!.subtract(Duration(days: experiment.reservationDeadlineDays));
      return now.isBefore(deadline);
    }

    // デフォルトはキャンセル可能
    return true;
  }
}