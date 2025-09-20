import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/experiment_slot.dart';
import '../models/experiment_reservation.dart';
import 'notification_service.dart';
import 'google_calendar_service.dart';

/// 予約管理サービス
class ReservationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final GoogleCalendarService _calendarService = GoogleCalendarService();

  /// 実験の予約枠を取得
  Stream<List<ExperimentSlot>> getExperimentSlots(String experimentId) {
    return _firestore
        .collection('experiment_slots')
        .where('experimentId', isEqualTo: experimentId)
        .orderBy('startTime')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ExperimentSlot.fromFirestore(doc))
            .toList());
  }

  /// IDから予約枠を取得
  Future<ExperimentSlot> getSlotById(String slotId) async {
    final doc = await _firestore.collection('experiment_slots').doc(slotId).get();
    if (!doc.exists) {
      throw Exception('予約枠が見つかりません');
    }
    return ExperimentSlot.fromFirestore(doc);
  }

  /// 特定の日付の予約枠を取得
  Future<List<ExperimentSlot>> getSlotsByDate(String experimentId, DateTime date) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // まず実験IDでフィルタリング
      final snapshot = await _firestore
          .collection('experiment_slots')
          .where('experimentId', isEqualTo: experimentId)
          .get();

      // クライアント側で日付フィルタリング
      final slots = snapshot.docs
          .map((doc) => ExperimentSlot.fromFirestore(doc))
          .where((slot) => 
              slot.startTime.isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
              slot.startTime.isBefore(endOfDay))
          .toList();
      
      // 開始時刻でソート
      slots.sort((a, b) => a.startTime.compareTo(b.startTime));
      
      return slots;
    } catch (e) {
      return [];
    }
  }

  /// 予約枠を作成
  Future<void> createSlot(ExperimentSlot slot) async {
    await _firestore.collection('experiment_slots').add(slot.toFirestore());
  }

  /// 複数の予約枠を一括作成
  Future<void> createMultipleSlots(List<ExperimentSlot> slots) async {
    final batch = _firestore.batch();
    
    for (final slot in slots) {
      final docRef = _firestore.collection('experiment_slots').doc();
      batch.set(docRef, slot.toFirestore());
    }
    
    await batch.commit();
  }

  /// 予約枠を更新
  Future<void> updateSlot(String slotId, Map<String, dynamic> data) async {
    await _firestore.collection('experiment_slots').doc(slotId).update(data);
  }

  /// 予約枠を削除
  Future<void> deleteSlot(String slotId) async {
    // 予約がある場合は削除できないようにする
    final reservations = await getReservationsBySlot(slotId);
    if (reservations.isNotEmpty) {
      throw Exception('この予約枠には予約が存在するため削除できません');
    }
    
    await _firestore.collection('experiment_slots').doc(slotId).delete();
  }

  /// 予約を作成
  Future<String> createReservation({
    required String userId,
    required String experimentId,
    required String slotId,
  }) async {
    // トランザクションで予約枠の更新と予約の作成を同時に行う
    return await _firestore.runTransaction((transaction) async {
      // 予約枠の情報を取得
      final slotDoc = await transaction.get(
        _firestore.collection('experiment_slots').doc(slotId),
      );
      
      if (!slotDoc.exists) {
        throw Exception('予約枠が見つかりません');
      }
      
      final slot = ExperimentSlot.fromFirestore(slotDoc);
      
      // 予約可能かチェック
      if (!slot.canReserve) {
        throw Exception('この予約枠は予約できません');
      }
      
      // 予約を作成
      final reservationRef = _firestore.collection('experiment_reservations').doc();
      final reservation = ExperimentReservation(
        id: reservationRef.id,
        userId: userId,
        experimentId: experimentId,
        slotId: slotId,
        reservedAt: DateTime.now(),
        status: ReservationStatus.confirmed,
      );
      
      transaction.set(reservationRef, reservation.toFirestore());
      
      // 予約枠の参加者数を更新
      transaction.update(
        _firestore.collection('experiment_slots').doc(slotId),
        {'currentParticipants': slot.currentParticipants + 1},
      );
      
      return reservationRef.id;
    });
  }

  /// 予約をキャンセル
  Future<void> cancelReservation(String reservationId, String? reason) async {
    // Googleカレンダーから削除（トランザクション前に実行）
    try {
      if (await _calendarService.isCalendarEnabled()) {
        await _calendarService.removeReservationFromCalendar(reservationId);
      }
    } catch (e) {
    }
    
    await _firestore.runTransaction((transaction) async {
      // 予約情報を取得
      final reservationDoc = await transaction.get(
        _firestore.collection('experiment_reservations').doc(reservationId),
      );
      
      if (!reservationDoc.exists) {
        throw Exception('予約が見つかりません');
      }
      
      final reservation = ExperimentReservation.fromFirestore(reservationDoc);
      
      // 予約枠の参加者数を減らす
      final slotDoc = await transaction.get(
        _firestore.collection('experiment_slots').doc(reservation.slotId),
      );
      
      if (slotDoc.exists) {
        final slot = ExperimentSlot.fromFirestore(slotDoc);
        transaction.update(
          _firestore.collection('experiment_slots').doc(reservation.slotId),
          {'currentParticipants': slot.currentParticipants - 1},
        );
      }
      
      // 予約状態を更新
      transaction.update(
        _firestore.collection('experiment_reservations').doc(reservationId),
        {
          'status': ReservationStatus.cancelled.name,
          'cancelReason': reason,
        },
      );
    });
    
    // 実験作成者に通知を送信（トランザクション外で実行）
    try {
      // 予約情報を再取得
      final reservationDoc = await _firestore.collection('experiment_reservations').doc(reservationId).get();
      if (!reservationDoc.exists) return;
      
      final reservation = ExperimentReservation.fromFirestore(reservationDoc);
      
      // 実験情報を取得
      final experimentDoc = await _firestore.collection('experiments').doc(reservation.experimentId).get();
      if (experimentDoc.exists) {
        final experimentData = experimentDoc.data()!;
        final creatorId = experimentData['creatorId'] as String?;
        final experimentTitle = experimentData['title'] as String? ?? '実験';
        
        // キャンセルしたユーザーの名前を取得
        String participantName = 'ユーザー';
        final userDoc = await _firestore.collection('users').doc(reservation.userId).get();
        if (userDoc.exists) {
          participantName = userDoc.data()!['name'] as String? ?? 'ユーザー';
        }
        
        // 実験作成者に通知
        if (creatorId != null && creatorId != reservation.userId) {
          await _notificationService.createExperimentCancelledNotification(
            userId: creatorId,
            participantName: participantName,
            experimentTitle: experimentTitle,
            experimentId: reservation.experimentId,
            reason: reason,
          );
        }
      }
    } catch (notificationError) {
    }
  }

  /// ユーザーの予約を取得
  Stream<List<ExperimentReservation>> getUserReservations(String userId) {
    return _firestore
        .collection('experiment_reservations')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final reservations = snapshot.docs
              .map((doc) => ExperimentReservation.fromFirestore(doc))
              .toList();
          // クライアント側でソート（インデックス不要）
          reservations.sort((a, b) => b.reservedAt.compareTo(a.reservedAt));
          return reservations;
        });
  }

  /// 実験の予約を取得
  Future<List<ExperimentReservation>> getExperimentReservations(String experimentId) async {
    final snapshot = await _firestore
        .collection('experiment_reservations')
        .where('experimentId', isEqualTo: experimentId)
        .get();
    
    return snapshot.docs.map((doc) => ExperimentReservation.fromFirestore(doc)).toList();
  }

  /// 予約枠の予約を取得
  Future<List<ExperimentReservation>> getReservationsBySlot(String slotId) async {
    final snapshot = await _firestore
        .collection('experiment_reservations')
        .where('slotId', isEqualTo: slotId)
        .where('status', isEqualTo: ReservationStatus.confirmed.name)
        .get();
    
    return snapshot.docs.map((doc) => ExperimentReservation.fromFirestore(doc)).toList();
  }

  /// ユーザーが既に実験に予約しているかチェック
  Future<bool> hasUserReserved(String userId, String experimentId) async {
    final snapshot = await _firestore
        .collection('experiment_reservations')
        .where('userId', isEqualTo: userId)
        .where('experimentId', isEqualTo: experimentId)
        .where('status', isEqualTo: ReservationStatus.confirmed.name)
        .limit(1)
        .get();
    
    return snapshot.docs.isNotEmpty;
  }

  /// 予約枠の自動生成（日時範囲と間隔を指定）
  List<ExperimentSlot> generateSlots({
    required String experimentId,
    required DateTime startDate,
    required DateTime endDate,
    required List<TimeSlot> dailyTimeSlots,
    required int duration, // 分単位
    required int maxParticipants,
    List<DateTime> excludeDates = const [],
  }) {
    final slots = <ExperimentSlot>[];
    DateTime currentDate = startDate;

    while (!currentDate.isAfter(endDate)) {
      // 除外日をスキップ
      if (excludeDates.any((date) => 
          date.year == currentDate.year && 
          date.month == currentDate.month && 
          date.day == currentDate.day)) {
        currentDate = currentDate.add(const Duration(days: 1));
        continue;
      }

      // 各時間帯でスロットを生成
      for (final timeSlot in dailyTimeSlots) {
        final startTime = DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
          timeSlot.hour,
          timeSlot.minute,
        );
        final endTime = startTime.add(Duration(minutes: duration));

        slots.add(ExperimentSlot(
          id: '', // IDは後で設定
          experimentId: experimentId,
          startTime: startTime,
          endTime: endTime,
          maxParticipants: maxParticipants,
        ));
      }

      currentDate = currentDate.add(const Duration(days: 1));
    }

    return slots;
  }
}

/// 時間スロット
class TimeSlot {
  final int hour;
  final int minute;

  TimeSlot({required this.hour, this.minute = 0});
}