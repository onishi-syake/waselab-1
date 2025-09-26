import 'package:cloud_firestore/cloud_firestore.dart';
import 'time_slot.dart';
import 'date_time_slot.dart';

/// 実験種別
enum ExperimentType {
  online('オンライン'),
  onsite('対面'),
  survey('アンケートのみ');

  final String label;
  const ExperimentType(this.label);
}

/// 日程設定方法
enum ScheduleType {
  fixed('固定日時'),         // 全員同じ日時
  reservation('予約制'),     // 複数の時間枠から参加者が選択
  individual('個別調整');    // 参加者と話し合って決定

  final String label;
  const ScheduleType(this.label);
  
  static ScheduleType fromString(String value) {
    return ScheduleType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ScheduleType.fixed,
    );
  }
}

/// 実験ステータス
enum ExperimentStatus {
  recruiting('募集中'),
  ongoing('進行中'),
  waitingEvaluation('評価待ち'),
  completed('完了');

  final String label;
  const ExperimentStatus(this.label);

  static ExperimentStatus fromString(String value) {
    return ExperimentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ExperimentStatus.recruiting,
    );
  }
}

/// 実験データモデル
class Experiment {
  final String id;
  final String title;           // 実験タイトル
  final String description;      // 実験概要（カードに表示）
  final String? detailedContent; // 詳細内容（詳細画面のみ表示）
  final int reward;             // 報酬（円）
  final String location;         // 場所
  final ExperimentType type;     // 種別
  final bool isPaid;            // 有償/無償
  final String creatorId;       // 作成者ID
  final DateTime createdAt;      // 作成日時
  final DateTime? recruitmentStartDate; // 募集開始日
  final DateTime? recruitmentEndDate;   // 募集終了日
  final DateTime? experimentPeriodStart; // 実験実施期間開始
  final DateTime? experimentPeriodEnd;   // 実験実施期間終了
  final bool allowFlexibleSchedule;      // 柔軟なスケジュール調整可能（互換性のため保持）
  final ScheduleType scheduleType;       // 日程設定方法
  final String? labName;         // 研究室名
  final int? duration;          // 所要時間（分）
  final int? maxParticipants;   // 最大参加者数
  final List<String> requirements; // 参加条件
  final List<String> participants; // 参加者IDリスト
  final List<TimeSlot> timeSlots; // 利用可能な時間枠リスト（曜日ベース、互換性のため保持）
  final List<DateTimeSlot> dateTimeSlots; // 日付ベースの時間枠リスト
  final int simultaneousCapacity; // 同時実験可能人数（デフォルト1）
  final DateTime? fixedExperimentDate; // 固定日時の場合の実施日
  final Map<String, int>? fixedExperimentTime; // 固定日時の場合の実施時刻
  final int reservationDeadlineDays; // 予約締切日数（デフォルト1日前）
  final ExperimentStatus status; // 実験のステータス
  final DateTime? completedAt; // 完了日時
  final Map<String, Map<String, dynamic>>? evaluations; // 評価状態 {userId: {evaluated: bool, evaluationType: string}}
  final Map<String, Map<String, dynamic>>? participantEvaluations; // 参加者ごとの個別評価状態
  final DateTime? actualStartDate; // 実際の実験開始日
  final String? surveyUrl; // アンケートURL（アンケートタイプの実験用）
  final List<String> consentItems; // 特別な同意項目リスト
  final String? preSurveyUrl; // 事前アンケートURL
  final String? preSurveyTemplateId; // 事前アンケートテンプレートID
  final String? experimentSurveyTemplateId; // 実験アンケートテンプレートID
  final String? postSurveyUrl; // 事後アンケートURL
  final String? postSurveyTemplateId; // 事後アンケートテンプレートID
  
  // 旧フィールドとの互換性のため
  DateTime? get experimentDate => recruitmentStartDate;
  DateTime? get endDate => recruitmentEndDate;
  String? get experimentSurveyUrl => surveyUrl; // surveyUrlを実験アンケートURLとして扱う

  Experiment({
    required this.id,
    required this.title,
    required this.description,
    this.detailedContent,
    required this.reward,
    required this.location,
    required this.type,
    required this.isPaid,
    required this.creatorId,
    required this.createdAt,
    this.recruitmentStartDate,
    this.recruitmentEndDate,
    this.experimentPeriodStart,
    this.experimentPeriodEnd,
    this.allowFlexibleSchedule = false,
    ScheduleType? scheduleType,
    this.labName,
    this.duration,
    this.maxParticipants,
    this.requirements = const [],
    this.participants = const [],
    this.timeSlots = const [],
    this.dateTimeSlots = const [],
    this.simultaneousCapacity = 1,
    this.fixedExperimentDate,
    this.fixedExperimentTime,
    this.reservationDeadlineDays = 1,
    this.status = ExperimentStatus.recruiting,
    this.completedAt,
    this.evaluations,
    this.participantEvaluations,
    this.actualStartDate,
    this.surveyUrl,
    this.consentItems = const [],
    this.preSurveyUrl,
    this.preSurveyTemplateId,
    this.experimentSurveyTemplateId,
    this.postSurveyUrl,
    this.postSurveyTemplateId,
  }) : scheduleType = scheduleType ?? (allowFlexibleSchedule ? ScheduleType.individual : ScheduleType.fixed);

  /// FirestoreのドキュメントからExperimentを作成
  factory Experiment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return Experiment(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      detailedContent: data['detailedContent'],
      reward: data['reward'] ?? 0,
      location: data['location'] ?? '',
      type: ExperimentType.values.firstWhere(
        (e) => e.name == (data['type'] ?? 'online'),
        orElse: () => ExperimentType.online,
      ),
      isPaid: data['isPaid'] ?? false,
      creatorId: data['creatorId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      recruitmentStartDate: (data['recruitmentStartDate'] as Timestamp?)?.toDate() ??
          (data['experimentDate'] as Timestamp?)?.toDate(), // 旧フィールドとの互換性
      recruitmentEndDate: (data['recruitmentEndDate'] as Timestamp?)?.toDate() ??
          (data['endDate'] as Timestamp?)?.toDate(), // 旧フィールドとの互換性
      experimentPeriodStart: (data['experimentPeriodStart'] as Timestamp?)?.toDate(),
      experimentPeriodEnd: (data['experimentPeriodEnd'] as Timestamp?)?.toDate(),
      allowFlexibleSchedule: data['allowFlexibleSchedule'] ?? false,
      scheduleType: data['scheduleType'] != null 
        ? ScheduleType.fromString(data['scheduleType']) 
        : (data['allowFlexibleSchedule'] == true ? ScheduleType.individual : ScheduleType.fixed),
      labName: data['labName'],
      duration: data['duration'],
      maxParticipants: data['maxParticipants'],
      requirements: data['requirements'] != null
        ? (data['requirements'] is String 
            ? [data['requirements'] as String]  // 文字列の場合は配列に変換
            : List<String>.from(data['requirements'] as List))
        : [],
      participants: List<String>.from(data['participants'] ?? []),
      timeSlots: (data['timeSlots'] as List<dynamic>?)
          ?.map((slot) => TimeSlot.fromJson(slot as Map<String, dynamic>))
          .toList() ?? [],
      dateTimeSlots: (data['dateTimeSlots'] as List<dynamic>?)
          ?.map((slot) => DateTimeSlot.fromJson(slot as Map<String, dynamic>))
          .toList() ?? [],
      simultaneousCapacity: data['simultaneousCapacity'] ?? 1,
      fixedExperimentDate: (data['fixedExperimentDate'] as Timestamp?)?.toDate(),
      fixedExperimentTime: data['fixedExperimentTime'] != null
          ? Map<String, int>.from(data['fixedExperimentTime'] as Map)
          : null,
      reservationDeadlineDays: data['reservationDeadlineDays'] ?? 1,
      status: data['status'] != null 
        ? ExperimentStatus.fromString(data['status'])
        : ExperimentStatus.recruiting,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      evaluations: data['evaluations'] != null
        ? Map<String, Map<String, dynamic>>.from(data['evaluations'] as Map)
        : null,
      actualStartDate: (data['actualStartDate'] as Timestamp?)?.toDate(),
      surveyUrl: data['surveyUrl'],
      consentItems: List<String>.from(data['consentItems'] ?? []),
      preSurveyUrl: data['preSurveyUrl'],
      preSurveyTemplateId: data['preSurveyTemplateId'],
      experimentSurveyTemplateId: data['experimentSurveyTemplateId'],
      postSurveyUrl: data['postSurveyUrl'],
      postSurveyTemplateId: data['postSurveyTemplateId'],
      participantEvaluations: data['participantEvaluations'] != null
        ? Map<String, Map<String, dynamic>>.from(
            (data['participantEvaluations'] as Map).map(
              (key, value) => MapEntry(key.toString(), Map<String, dynamic>.from(value as Map)),
            ),
          )
        : null,
    );
  }

  /// ExperimentをFirestoreに保存する形式に変換
  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'detailedContent': detailedContent,
      'reward': reward,
      'location': location,
      'type': type.name,
      'isPaid': isPaid,
      'creatorId': creatorId,
      'createdAt': Timestamp.fromDate(createdAt),
      'recruitmentStartDate': recruitmentStartDate != null 
        ? Timestamp.fromDate(recruitmentStartDate!) 
        : null,
      'recruitmentEndDate': recruitmentEndDate != null
        ? Timestamp.fromDate(recruitmentEndDate!)
        : null,
      'experimentPeriodStart': experimentPeriodStart != null
        ? Timestamp.fromDate(experimentPeriodStart!)
        : null,
      'experimentPeriodEnd': experimentPeriodEnd != null
        ? Timestamp.fromDate(experimentPeriodEnd!)
        : null,
      'allowFlexibleSchedule': allowFlexibleSchedule,
      'scheduleType': scheduleType.name,
      'labName': labName,
      'duration': duration,
      'maxParticipants': maxParticipants,
      'requirements': requirements,
      'participants': participants,
      'timeSlots': timeSlots.map((slot) => slot.toJson()).toList(),
      'dateTimeSlots': dateTimeSlots.map((slot) => slot.toJson()).toList(),
      'simultaneousCapacity': simultaneousCapacity,
      'fixedExperimentDate': fixedExperimentDate != null
        ? Timestamp.fromDate(fixedExperimentDate!)
        : null,
      'fixedExperimentTime': fixedExperimentTime,
      'reservationDeadlineDays': reservationDeadlineDays,
      'status': status.name,
      'completedAt': completedAt != null
        ? Timestamp.fromDate(completedAt!)
        : null,
      'evaluations': evaluations,
      'participantEvaluations': participantEvaluations,
      'actualStartDate': actualStartDate != null
        ? Timestamp.fromDate(actualStartDate!)
        : null,
      'surveyUrl': surveyUrl,
      'consentItems': consentItems,
      'preSurveyUrl': preSurveyUrl,
      'preSurveyTemplateId': preSurveyTemplateId,
      'experimentSurveyTemplateId': experimentSurveyTemplateId,
      'postSurveyUrl': postSurveyUrl,
      'postSurveyTemplateId': postSurveyTemplateId,
    };
  }

  /// 実験が評価可能かどうかをチェック
  bool canEvaluate(String userId) {
    // 基本的なチェック：実験者または参加者でない場合は評価不可
    if (!(creatorId == userId || participants.contains(userId))) {
      return false;
    }

    // 既に評価済みの場合は評価不可
    if (hasEvaluated(userId)) {
      return false;
    }

    // アンケート型は日時制限なし
    if (type == ExperimentType.survey) {
      return true;
    }

    // 固定日時の実験の場合
    if (fixedExperimentDate != null) {
      // 実施日時を過ぎているかチェック
      final experimentDateTime = fixedExperimentDate!;
      if (fixedExperimentTime != null) {
        // 時刻情報がある場合は時刻も考慮
        final hour = fixedExperimentTime!['hour'] ?? 0;
        final minute = fixedExperimentTime!['minute'] ?? 0;
        final scheduledDateTime = DateTime(
          experimentDateTime.year,
          experimentDateTime.month,
          experimentDateTime.day,
          hour,
          minute,
        );
        return DateTime.now().isAfter(scheduledDateTime);
      }
      // 日付のみの場合はその日の終わり（23:59）を基準にする
      final endOfDay = DateTime(
        experimentDateTime.year,
        experimentDateTime.month,
        experimentDateTime.day,
        23,
        59,
      );
      return DateTime.now().isAfter(endOfDay);
    }

    // 予約制の実験で参加者の個別スケジュールがある場合
    if (scheduleType == ScheduleType.reservation && participants.contains(userId) && participantEvaluations != null) {
      final participantInfo = participantEvaluations![userId];
      if (participantInfo != null && participantInfo['scheduledDate'] != null) {
        final scheduledDate = (participantInfo['scheduledDate'] as Timestamp).toDate();
        return DateTime.now().isAfter(scheduledDate);
      }
    }

    // 柔軟な日程調整の実験で参加者の場合
    if (allowFlexibleSchedule && participants.contains(userId) && participantEvaluations != null) {
      final participantInfo = participantEvaluations![userId];
      if (participantInfo != null && participantInfo['scheduledDate'] != null) {
        final scheduledDate = (participantInfo['scheduledDate'] as Timestamp).toDate();
        return DateTime.now().isAfter(scheduledDate);
      }
    }

    // 実験期間が設定されている場合は、実験開始日以降のみ評価可能
    if (experimentPeriodStart != null) {
      return DateTime.now().isAfter(experimentPeriodStart!);
    }

    // その他の場合（日時指定なしの実験など）は評価可能
    return true;
  }

  /// ユーザーが既に評価済みかどうかをチェック
  bool hasEvaluated(String userId) {
    if (evaluations == null) return false;
    final userEval = evaluations![userId];
    return userEval != null && userEval['evaluated'] == true;
  }

  /// 実験が将来の予定かどうかをチェック
  bool isScheduledFuture(String userId) {
    // アンケート型は常に現在実施可能
    if (type == ExperimentType.survey) {
      return false;
    }
    
    // 固定日時の実験の場合
    if (fixedExperimentDate != null) {
      final experimentDateTime = fixedExperimentDate!;
      if (fixedExperimentTime != null) {
        // 時刻情報がある場合
        final hour = fixedExperimentTime!['hour'] ?? 0;
        final minute = fixedExperimentTime!['minute'] ?? 0;
        final scheduledDateTime = DateTime(
          experimentDateTime.year,
          experimentDateTime.month,
          experimentDateTime.day,
          hour,
          minute,
        );
        return DateTime.now().isBefore(scheduledDateTime);
      }
      // 日付のみの場合
      return DateTime.now().isBefore(experimentDateTime);
    }
    
    // 柔軟な日程調整の実験で参加者の場合
    if (allowFlexibleSchedule && participants.contains(userId) && participantEvaluations != null) {
      final participantInfo = participantEvaluations![userId];
      if (participantInfo != null && participantInfo['scheduledDate'] != null) {
        final scheduledDate = (participantInfo['scheduledDate'] as Timestamp).toDate();
        return DateTime.now().isBefore(scheduledDate);
      }
    }
    
    // その他の場合は将来の予定ではない
    return false;
  }

  /// 実験が自動完了の対象かどうかをチェック（1週間経過）
  bool shouldAutoComplete() {
    // 既に完了している場合はスキップ
    if (status == ExperimentStatus.completed) return false;

    // 評価待ち状態の場合：最初の評価（actualStartDate）から1週間経過
    if (status == ExperimentStatus.waitingEvaluation) {
      final startDate = actualStartDate;
      if (startDate != null) {
        final oneWeekLater = startDate.add(const Duration(days: 7));
        if (DateTime.now().isAfter(oneWeekLater)) return true;
      }
    }

    // その他の状態：実験期間終了から1週間経過
    final endDate = experimentPeriodEnd;
    if (endDate != null) {
      final oneWeekLater = endDate.add(const Duration(days: 7));
      return DateTime.now().isAfter(oneWeekLater);
    }

    return false;
  }

  /// 特定の参加者との相互評価が完了しているかをチェック
  bool isMutuallyCompletedWithUser(String userId) {
    if (participantEvaluations == null) return false;
    final userEval = participantEvaluations![userId];
    if (userEval == null) return false;
    return userEval['mutuallyCompleted'] ?? false;
  }

  /// すべての参加者との相互評価が完了しているかをチェック
  bool areAllMutualEvaluationsCompleted() {
    if (participants.isEmpty) return true;
    if (participantEvaluations == null) return false;

    for (final participantId in participants) {
      if (!isMutuallyCompletedWithUser(participantId)) {
        return false;
      }
    }
    return true;
  }

  /// 参加者視点で実験が完了しているかをチェック
  bool isCompletedForParticipant(String participantId) {
    // まず参加者でない場合はfalse
    if (!participants.contains(participantId)) return false;

    // 参加者個別の相互評価が完了している場合
    if (isMutuallyCompletedWithUser(participantId)) return true;

    // 実験全体が完了済みの場合も完了とする
    if (status == ExperimentStatus.completed) return true;

    return false;
  }

  /// 実験者視点で実験が完了しているかをチェック
  bool isCompletedForExperimenter() {
    // 実験全体のステータスが完了の場合のみtrue
    // （実施期間終了 or 満員で全員評価完了）
    return status == ExperimentStatus.completed;
  }

  /// 実験が評価待ち状態かどうかをチェック（UI表示用）
  bool isWaitingForEvaluation(String userId) {
    // 実験者の場合
    if (creatorId == userId) {
      // 未評価の参加者がいる場合は評価待ち
      if (participantEvaluations != null) {
        for (final participantId in participants) {
          final userEval = participantEvaluations![participantId] ?? {};
          final creatorEvaluated = userEval['creatorEvaluated'] ?? false;
          if (!creatorEvaluated) return true;
        }
      }
      return false;
    }

    // 参加者の場合
    if (participants.contains(userId)) {
      // 相互評価が未完了で、評価可能な場合は評価待ち
      if (!isMutuallyCompletedWithUser(userId) && canEvaluate(userId) && !hasEvaluated(userId)) {
        return true;
      }
    }

    return false;
  }

  /// 自分は評価済みだが相手の評価待ちかどうかをチェック（新仕様）
  bool isWaitingOthersEvaluation(String userId) {
    // 参加者の場合のみチェック
    if (!participants.contains(userId)) return false;

    // 自分が既に評価済みでないと評価待ちではない
    if (!hasEvaluated(userId)) return false;

    // 相互評価が完了していない場合は相手の評価待ち
    return !isMutuallyCompletedWithUser(userId);
  }

  /// 評価可能だが未評価かどうかをチェック（新仕様）
  bool canEvaluateButNotYet(String userId) {
    // 評価可能で、かつまだ評価していない
    return canEvaluate(userId) && !hasEvaluated(userId);
  }
}