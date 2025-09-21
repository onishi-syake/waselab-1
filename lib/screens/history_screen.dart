import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/experiment_service.dart';
import '../services/reservation_service.dart';
import '../models/app_user.dart';
import '../models/experiment.dart';
import '../models/experiment_reservation.dart';
import 'experiment_detail_screen.dart';
import 'experiment_evaluation_screen.dart';
import 'experiment_management_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ExperimentService _experimentService = ExperimentService();
  final ReservationService _reservationService = ReservationService();
  
  AppUser? _currentUser;
  bool _isLoading = true;
  late TabController _tabController;
  
  List<Experiment> _participatedExperiments = [];
  List<Experiment> _createdExperiments = [];
  List<ExperimentReservation> _userReservations = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      var user = await _authService.getCurrentAppUser();
      if (user != null) {
        final participated = await _experimentService.getUserParticipatedExperiments(user.uid);
        final created = await _experimentService.getUserCreatedExperiments(user.uid);
        
        List<ExperimentReservation> reservations = [];
        try {
          final reservationsStream = _reservationService.getUserReservations(user.uid);
          reservations = await reservationsStream.first;
        } catch (e) {
        }
        
        if (mounted) {
          setState(() {
            _currentUser = user;
            _participatedExperiments = participated;
            _createdExperiments = created;
            _userReservations = reservations;
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('履歴'),
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
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('参加履歴'),
                  if (_getParticipatedExperimentsUnevaluatedCount() > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_getParticipatedExperimentsUnevaluatedCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('募集履歴'),
                  if (_getCreatedExperimentsUnevaluatedCount() > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_getCreatedExperimentsUnevaluatedCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  if (_getCreatedExperimentsPostSurveyCount() > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_getCreatedExperimentsPostSurveyCount()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildParticipatedExperimentsTab(),
          _buildCreatedExperimentsTab(),
        ],
      ),
    );
  }

  Widget _buildParticipatedExperimentsTab() {
    final scheduledExperiments = <Experiment>[];
    final waitingEvaluationExperiments = <Experiment>[];
    final completedExperiments = <Experiment>[];

    for (final experiment in _participatedExperiments) {
      final userId = _currentUser?.uid ?? '';

      // 相互評価が完了している場合は完了済み
      if (experiment.isCompletedForParticipant(userId)) {
        completedExperiments.add(experiment);
      }
      // 評価待ちの場合
      else if (experiment.isWaitingForEvaluation(userId)) {
        waitingEvaluationExperiments.add(experiment);
      }
      // 将来の実験の場合
      else if (experiment.isScheduledFuture(userId)) {
        scheduledExperiments.add(experiment);
      }
      // その他（既に自分だけ評価済みなど）
      else {
        // 自分が既に評価済みの場合は評価待ち扱い（相手の評価待ち）
        if (experiment.hasEvaluated(userId)) {
          waitingEvaluationExperiments.add(experiment);
        } else {
          scheduledExperiments.add(experiment);
        }
      }
    }
    
    if (_participatedExperiments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '参加した実験がありません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (waitingEvaluationExperiments.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withValues(alpha: 0.2),
                  Colors.orange.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '相互評価のお願い',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '実験終了後は必ず相互評価を行ってください。相互評価により実験の完了が確認され、システムに正しく反映されます。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        
        if (scheduledExperiments.isNotEmpty) ...[
          _buildSectionHeader('参加予定', Icons.schedule, Colors.blue),
          ...scheduledExperiments.map((e) => _buildExperimentCard(e)),
          const SizedBox(height: 16),
        ],
        
        if (waitingEvaluationExperiments.isNotEmpty) ...[
          _buildSectionHeader('評価待ち', Icons.rate_review, Colors.orange),
          ...waitingEvaluationExperiments.map((e) => _buildExperimentCard(e)),
          const SizedBox(height: 16),
        ],
        
        if (completedExperiments.isNotEmpty) ...[
          _buildSectionHeader('完了済み', Icons.check_circle, Colors.green),
          ...completedExperiments.map((e) => _buildExperimentCard(e)),
        ],
      ],
    );
  }

  Widget _buildCreatedExperimentsTab() {
    if (_createdExperiments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.science_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '募集した実験がありません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    final ongoingExperiments = <Experiment>[];
    final completedExperiments = <Experiment>[];

    for (final experiment in _createdExperiments) {
      // 実験者視点で完了しているかチェック
      if (experiment.isCompletedForExperimenter()) {
        completedExperiments.add(experiment);
      } else {
        // 完了していない場合は進行中
        ongoingExperiments.add(experiment);
      }
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.grey[100],
            child: TabBar(
              indicatorColor: const Color(0xFF8E1728),
              indicatorWeight: 3,
              labelColor: const Color(0xFF8E1728),
              unselectedLabelColor: Colors.grey[600],
              tabs: [
                Tab(text: '進行中 (${ongoingExperiments.length})'),
                Tab(text: '完了済み (${completedExperiments.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildExperimentHistoryTab(ongoingExperiments, '進行中の実験'),
                _buildExperimentHistoryTab(completedExperiments, '完了した実験'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperimentHistoryTab(List<Experiment> experiments, String emptyMessage) {
    if (experiments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '$emptyMessageがありません',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    final hasUnevaluated = experiments.any((exp) => _getUnevaluatedParticipantCount(exp) > 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasUnevaluated) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withValues(alpha: 0.2),
                  Colors.orange.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.amber,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '参加者への評価のお願い',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '実験終了後は必ず参加者の評価を行ってください。相互評価により実験の完了が確認されます。',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        ...experiments.map((experiment) {
          final isMyExperiment = experiment.creatorId == _currentUser?.uid;
          
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (isMyExperiment) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExperimentManagementScreen(
                        experiment: experiment,
                      ),
                    ),
                  ).then((_) {
                    _loadData();
                  });
                } else if (experiment.status == ExperimentStatus.waitingEvaluation &&
                    !experiment.hasEvaluated(_currentUser?.uid ?? '')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExperimentEvaluationScreen(
                        experiment: experiment,
                      ),
                    ),
                  ).then((result) {
                    if (result == true) {
                      _loadData();
                    }
                  });
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExperimentDetailScreen(
                        experiment: experiment,
                        isMyExperiment: isMyExperiment,
                      ),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getTypeColor(experiment.type),
                      child: Icon(
                        _getTypeIcon(experiment.type),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                experiment.title,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: _buildStatusBadge(experiment, isMyExperiment),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            experiment.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    experiment.experimentDate != null
                                      ? DateFormat('yyyy/MM/dd').format(experiment.experimentDate!)
                                      : '日程未定',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.payments, size: 14, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    experiment.isPaid ? '¥${experiment.reward}' : '無償',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: experiment.isPaid ? Colors.green[700] : Colors.grey[600],
                                      fontWeight: experiment.isPaid ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              if (isMyExperiment)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.people, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Text(
                                      '参加者: ${experiment.participants.length ?? 0}名',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: experiment.type == ExperimentType.online
                                ? Colors.blue.withValues(alpha: 0.1)
                                : experiment.type == ExperimentType.onsite
                                    ? Colors.orange.withValues(alpha: 0.1)
                                    : Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            experiment.type.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: _getTypeColor(experiment.type),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isMyExperiment) ...[
                          const SizedBox(height: 4),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8E1728).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.settings,
                                  size: 16,
                                  color: Color(0xFF8E1728),
                                ),
                              ),
                              // URL送信可能バッジ
                              if (_getUrlSendableParticipantCount(experiment) > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${_getUrlSendableParticipantCount(experiment)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              // 評価可能バッジ
                              if (_getUnevaluatedParticipantCount(experiment) > 0)
                                Positioned(
                                  top: -4,
                                  left: -4,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 1.5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${_getUnevaluatedParticipantCount(experiment)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    // アンケートボタンを追加
                    if (!isMyExperiment && (experiment.preSurveyUrl != null || experiment.postSurveyUrl != null || experiment.experimentSurveyUrl != null)) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () => _showSurveyUrlsDialog(experiment),
                        icon: const Icon(
                          Icons.quiz_outlined,
                          size: 20,
                          color: Colors.purple,
                        ),
                        tooltip: 'アンケートURLを確認',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildExperimentCard(Experiment experiment) {
    final isMyExperiment = experiment.creatorId == _currentUser?.uid;
    final isParticipant = experiment.participants.contains(_currentUser?.uid ?? '');
    final hasEvaluated = experiment.hasEvaluated(_currentUser?.uid ?? '');
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ExperimentDetailScreen(
                experiment: experiment,
                isMyExperiment: isMyExperiment,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _getTypeColor(experiment.type),
                child: Icon(
                  _getTypeIcon(experiment.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          experiment.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (experiment.type == ExperimentType.survey && 
                            isParticipant && 
                            !isMyExperiment) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              experiment.surveyUrl != null ? Icons.link : Icons.chat,
                              size: 16,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      experiment.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (experiment.isPaid)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.monetization_on, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                '¥${experiment.reward}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        if (experiment.location.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Flexible(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final locationLength = experiment.location.length;
                                    double fontSize = 12;
                                    
                                    // 文字数に応じてフォントサイズを調整
                                    if (locationLength > 20) {
                                      fontSize = 11;
                                    }
                                    if (locationLength > 30) {
                                      fontSize = 10;
                                    }
                                    if (locationLength > 40) {
                                      fontSize = 9;
                                    }
                                    
                                    return Text(
                                      experiment.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: fontSize,
                                        color: Colors.grey[600],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    // アンケートURLの表示
                    if (isParticipant && !isMyExperiment) ...[
                      if (experiment.preSurveyUrl != null) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _showSurveyUrlDialog('事前アンケート', experiment.preSurveyUrl!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fact_check, size: 12, color: Colors.purple.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '事前アンケート',
                                  style: TextStyle(fontSize: 11, color: Colors.purple.shade700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (experiment.postSurveyUrl != null) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _showSurveyUrlDialog('事後アンケート', experiment.postSurveyUrl!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fact_check_outlined, size: 12, color: Colors.deepOrange.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '事後アンケート',
                                  style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (experiment.isScheduledFuture(_currentUser?.uid ?? ''))
                    Container(
                      margin: const EdgeInsets.only(right: 4, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '実施前',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!hasEvaluated && experiment.canEvaluate(_currentUser?.uid ?? '')) 
                    Container(
                      margin: const EdgeInsets.only(right: 4, bottom: 4),
                      child: Material(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                        elevation: 2,
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ExperimentEvaluationScreen(
                                  experiment: experiment,
                                ),
                              ),
                            ).then((result) {
                              if (result == true) {
                                _loadData();
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '評価する',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (experiment.type == ExperimentType.survey && 
                      isParticipant && 
                      !isMyExperiment)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      child: Material(
                        color: Colors.purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: () {
                            _showSurveyUrlDialogForExperiment(experiment);
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  experiment.surveyUrl != null ? Icons.link : Icons.chat_bubble_outline,
                                  color: Colors.purple,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  experiment.surveyUrl != null ? 'URL' : '詳細',
                                  style: const TextStyle(
                                    color: Colors.purple,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
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
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// URL送信可能な参加者数を取得
  int _getUrlSendableParticipantCount(Experiment experiment) {
    if (experiment.postSurveyUrl == null || experiment.postSurveyUrl!.isEmpty) {
      return 0;
    }

    int count = 0;
    final experimentData = experiment.toFirestore();
    final participantEvals = experimentData['participantEvaluations'] as Map<String, dynamic>? ?? {};

    for (final participantId in experiment.participants) {
      final userEval = participantEvals[participantId] as Map<String, dynamic>? ?? {};
      final urlSent = userEval['postSurveyUrlSent'] ?? false;
      if (!urlSent) {
        count++;
      }
    }

    return count;
  }

  Widget _buildStatusBadge(Experiment experiment, bool isMyExperiment) {
    if (isMyExperiment) {
      final unevaluatedCount = _getUnevaluatedParticipantCount(experiment);
      
      if (unevaluatedCount > 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '未評価: $unevaluatedCount名',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
      
      if (experiment.status == ExperimentStatus.recruiting) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF8E1728).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '募集中',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8E1728),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
      
      if (experiment.status == ExperimentStatus.ongoing) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '実施中',
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '完了',
          style: TextStyle(
            fontSize: 11,
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    final hasEvaluated = experiment.hasEvaluated(_currentUser?.uid ?? '');
    
    if (!hasEvaluated && experiment.canEvaluate(_currentUser?.uid ?? '')) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '評価可能',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    if (hasEvaluated && experiment.status == ExperimentStatus.waitingEvaluation) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '相手の評価待ち',
          style: TextStyle(
            fontSize: 11,
            color: Colors.blue,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    if (experiment.status == ExperimentStatus.completed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '完了',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  Future<void> _showSurveyUrlDialogForExperiment(Experiment experiment) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.assignment, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                experiment.title,
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (experiment.surveyUrl != null) ...[
              const Text('アンケートURL:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      experiment.surveyUrl!,
                      style: const TextStyle(fontSize: 14, color: Colors.blue),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: experiment.surveyUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('URLをコピーしました'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('コピー'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final url = Uri.parse(experiment.surveyUrl!);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('開く'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8E1728),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'まだ回答していない場合は、URLから回答してください',
                        style: TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.chat, size: 20, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'アンケートURL未設定',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '実験者から個別チャットでアンケートの詳細が送られます',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
        ],
      ),
    );
  }

  int _getParticipatedExperimentsUnevaluatedCount() {
    int count = 0;
    for (final experiment in _participatedExperiments) {
      if (experiment.canEvaluate(_currentUser?.uid ?? '') && 
          !experiment.hasEvaluated(_currentUser?.uid ?? '') &&
          !experiment.isScheduledFuture(_currentUser?.uid ?? '')) {
        count++;
      }
    }
    return count;
  }

  int _getCreatedExperimentsUnevaluatedCount() {
    return _createdExperiments.fold<int>(
      0,
      (sum, exp) => sum + _getUnevaluatedParticipantCount(exp),
    );
  }

  int _getUnevaluatedParticipantCount(Experiment experiment) {
    int count = 0;
    final participantEvals = experiment.participantEvaluations ?? {};

    for (final participantId in experiment.participants) {
      final evalData = participantEvals[participantId] ?? {};
      if (!(evalData['creatorEvaluated'] ?? false) &&
          !experiment.isScheduledFuture(participantId)) {
        count++;
      }
    }

    return count;
  }

  int _getCreatedExperimentsPostSurveyCount() {
    return _createdExperiments.fold<int>(
      0,
      (sum, exp) => sum + _getPostSurveyPendingCount(exp),
    );
  }

  int _getPostSurveyPendingCount(Experiment experiment) {
    int count = 0;

    // 事後アンケートURLが設定されている実験のみチェック
    if (experiment.postSurveyUrl != null && experiment.postSurveyUrl!.isNotEmpty) {
      final participantEvals = experiment.participantEvaluations ?? {};

      for (final participantId in experiment.participants) {
        final evalData = participantEvals[participantId] ?? {};
        if (!(evalData['postSurveyUrlSent'] ?? false)) {
          count++;
        }
      }
    }

    return count;
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

  /// アンケートURLダイアログを表示
  void _showSurveyUrlDialog(String title, String surveyUrl) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('アンケートURL:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                surveyUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: surveyUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('URLをコピーしました')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('コピー'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final url = Uri.parse(surveyUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('開く'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(ExperimentType type) {
    switch (type) {
      case ExperimentType.online:
        return Icons.computer;
      case ExperimentType.onsite:
        return Icons.place;
      case ExperimentType.survey:
        return Icons.assignment;
    }
  }

  /// 実験参加がキャンセル可能かどうかを判定
  bool _canCancelParticipation(Experiment experiment) {
    // 既に評価済みの場合はキャンセル不可
    if (experiment.hasEvaluated(_currentUser?.uid ?? '')) {
      return false;
    }
    
    // 実験が完了している場合はキャンセル不可
    if (experiment.status == ExperimentStatus.completed) {
      return false;
    }
    
    // アンケート型は常にキャンセル可能
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
    
    // 柔軟な日程調整が可能な実験の場合
    if (experiment.allowFlexibleSchedule) {
      // 参加者の個別スケジュール情報がある場合
      if (experiment.participantEvaluations != null && 
          experiment.participantEvaluations!.containsKey(_currentUser?.uid)) {
        final participantInfo = experiment.participantEvaluations![_currentUser?.uid];
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
    
    // 実施前なら予約システムを使わない参加もキャンセル可能
    return experiment.isScheduledFuture(_currentUser?.uid ?? '');
  }
  
  /// アンケートURL表示ダイアログ
  void _showSurveyUrlsDialog(Experiment experiment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.quiz, color: Colors.purple),
            SizedBox(width: 8),
            Text('アンケートURL'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 事前アンケート
              if (experiment.preSurveyUrl != null && experiment.preSurveyUrl!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.assignment_outlined, size: 18, color: Colors.purple.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '事前アンケート',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          experiment.preSurveyUrl!,
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: experiment.preSurveyUrl!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URLをコピーしました'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('コピー', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final url = Uri.parse(experiment.preSurveyUrl!);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('開く', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // 事後アンケート
              if (experiment.experimentSurveyUrl != null && experiment.experimentSurveyUrl!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.quiz_outlined, size: 18, color: Colors.indigo.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '事後アンケート',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          experiment.experimentSurveyUrl!,
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: experiment.experimentSurveyUrl!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URLをコピーしました'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('コピー', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final url = Uri.parse(experiment.experimentSurveyUrl!);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('開く', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // 事後アンケート
              if (experiment.postSurveyUrl != null && experiment.postSurveyUrl!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.deepOrange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.fact_check_outlined, size: 18, color: Colors.deepOrange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            '事後アンケート',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          experiment.postSurveyUrl!,
                          style: const TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: experiment.postSurveyUrl!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('URLをコピーしました'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('コピー', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final url = Uri.parse(experiment.postSurveyUrl!);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(Icons.open_in_new, size: 14),
                              label: const Text('開く', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (experiment.preSurveyUrl == null && experiment.experimentSurveyUrl == null && experiment.postSurveyUrl == null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'アンケートURLが設定されていません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ],
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

  /// 予約がキャンセル可能かどうかを判定（予約システム使用時）
  bool _canCancelReservation(Experiment experiment) {
    // 実験に対する確定済み予約を検索
    final reservation = _userReservations.firstWhere(
      (r) => r.experimentId == experiment.id && r.status == ReservationStatus.confirmed,
      orElse: () => ExperimentReservation(
        id: '',
        userId: '',
        experimentId: '',
        slotId: '',
        reservedAt: DateTime.now(),
        status: ReservationStatus.cancelled,
      ),
    );

    if (reservation.id.isEmpty) {
      // 予約システムを使っていない場合は、通常の参加キャンセル判定を使用
      return _canCancelParticipation(experiment);
    }

    // 予約キャンセル可否を判定
    return reservation.canCancel(experiment);
  }

  /// キャンセル確認ダイアログを表示
  Future<void> _showCancelConfirmDialog(Experiment experiment) async {
    final TextEditingController reasonController = TextEditingController();

    // 予約があるか確認
    final hasReservation = _userReservations.any(
      (r) => r.experimentId == experiment.id && r.status == ReservationStatus.confirmed,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hasReservation ? '予約のキャンセル' : '参加のキャンセル'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasReservation
                ? 'この実験の予約をキャンセルしますか？'
                : 'この実験への参加をキャンセルしますか？',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'キャンセル理由（任意）',
                hintText: '急用のため、体調不良など...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('戻る'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('キャンセルする'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      await _cancelReservation(experiment, reasonController.text);
    }
    
    reasonController.dispose();
  }

  /// 予約をキャンセル
  Future<void> _cancelReservation(Experiment experiment, String reason) async {
    try {
      // 実験に対する予約を検索
      final reservation = _userReservations.firstWhere(
        (r) => r.experimentId == experiment.id && r.status == ReservationStatus.confirmed,
        orElse: () => ExperimentReservation(
          id: '',
          userId: '',
          experimentId: '',
          slotId: '',
          reservedAt: DateTime.now(),
          status: ReservationStatus.cancelled,
        ),
      );
      
      if (reservation.id.isNotEmpty) {
        // 予約システムを使った予約のキャンセル
        await _reservationService.cancelReservation(reservation.id, reason.isNotEmpty ? reason : null);
      } else {
        // 通常の実験参加のキャンセル（participantsリストから削除）
        final experimentService = ExperimentService();
        await experimentService.cancelParticipation(experiment.id, _currentUser!.uid, reason: reason.isNotEmpty ? reason : null);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('参加をキャンセルしました'),
            backgroundColor: Colors.green,
          ),
        );
        
        // データを再読み込み
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('キャンセルに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}