import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';
import '../patient/medicine_list_screen.dart';

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  final _authRepo = AuthRepository();
  String? _name;
  int? _userId;
  String? _token;
  List<dynamic> _patients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading && _token != null) {
      _loadDashboard();
    }
  }

  Future<void> _init() async {
    _name = await Storage.getUserName();
    _userId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (_userId == null || _token == null) return;
    try {
      final res = await ApiClient.get(
        '/guardian/dashboard',
        token: _token,
        queryParams: {'guardian_id': _userId.toString()},
      );
      if (mounted) {
        setState(() {
          _patients = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      if (_token != null) {
        await _authRepo.logout(token: _token!);
      }
    } catch (_) {
      // ignore and continue local logout
    }
    await Storage.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'taken':
        return '복약 완료';
      case 'missed':
        return '미복용';
      default:
        return '대기중';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'taken':
        return Colors.green;
      case 'missed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _timeSlotLabel(String slot) {
    switch (slot) {
      case 'morning':
        return '아침';
      case 'lunch':
        return '점심';
      case 'dinner':
        return '저녁';
      case 'bedtime':
        return '취침';
      default:
        return slot;
    }
  }

  // custom 슬롯은 실제 scheduled_time을 표시
  String _scheduleLabel(dynamic schedule) {
    final slot = schedule['time_slot'] as String? ?? '';
    if (slot == 'custom') {
      return _formatScheduledTime(schedule['scheduled_time'] as String?);
    }
    return _timeSlotLabel(slot);
  }

  String _formatScheduledTime(String? raw) {
    if (raw == null || raw.isEmpty) return '--:--';
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('보호자 모드'),
        automaticallyImplyLeading: false,
        actions: [
          Builder(builder: (ctx) {
            final totalMissed = _patients.fold<int>(
              0,
              (sum, p) => sum + ((p['missed_count'] as int?) ?? 0),
            );
            if (totalMissed == 0) return const SizedBox.shrink();
            return Stack(
              alignment: Alignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.notifications, color: Colors.red),
                ),
                Positioned(
                  top: 8,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Text(
                      '$totalMissed',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          }),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: '내 정보',
            onPressed: () => Navigator.pushNamed(context, '/profile'),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '안녕하세요, ${_name ?? ''}님 👋',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '가족의 오늘 복약 현황이에요',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                    if (_patients.isEmpty)
                      _buildEmptyState()
                    else ...[
                      _buildMissedAlert(),
                      ..._patients.map((p) => _buildPatientCard(p)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // 전체 환자의 미복약 건수 합산해서 경고 카드 표시
  Widget _buildMissedAlert() {
    final totalMissed = _patients.fold<int>(
      0,
      (sum, p) => sum + ((p['missed_count'] as int?) ?? 0),
    );
    if (totalMissed == 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '미복약 $totalMissed건이 있어요!',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '아래 현황을 확인하고 가족에게 연락해보세요',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.people_outline, size: 48, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            '연동된 가족이 없어요',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          SizedBox(height: 4),
          Text(
            '가족 연동을 먼저 진행해주세요',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _openMedicineManager(dynamic patient) async {
    final patientId = patient['patient_id'] as int?;
    if (patientId == null) return;
    final patientName = patient['patient_name'] as String? ?? '환자';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicineListScreen(
          patientId: patientId,
          patientName: patientName,
          allowManage: true,
        ),
      ),
    );

    await _loadDashboard();
  }

  Widget _buildPatientCard(dynamic patient) {
    final schedules = patient['today_schedules'] as List<dynamic>? ?? [];
    final adherence = patient['adherence_rate_7days'] as int? ?? 0;
    final missedCount = patient['missed_count'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 환자 헤더
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    patient['patient_name'] as String? ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '7일 이행률 $adherence%',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    if (missedCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '미복용 $missedCount건',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 스케줄 목록
          if (schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('오늘 스케줄이 없어요',
                  style: TextStyle(color: AppTheme.textSecondary)),
            )
          else
            ...schedules.map((s) => _buildScheduleRow(s)),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openMedicineManager(patient),
                icon: const Icon(Icons.medication_outlined, size: 16),
                label: const Text('약 관리'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildScheduleRow(dynamic schedule) {
    final status = schedule['status'] as String? ?? 'pending';
    final authMethod = schedule['auth_method'] as String? ?? '';
    final photoUrl = schedule['photo_url'] as String? ?? '';
    final hasPhoto =
        status == 'taken' && authMethod == 'photo' && photoUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _scheduleLabel(schedule),
              style: TextStyle(
                  color: _statusColor(status),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${schedule['medicine_name']}  ${schedule['dose']}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 6),
          if (hasPhoto)
            GestureDetector(
              onTap: () => _showPhoto(photoUrl),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt,
                        size: 12, color: Colors.orange.shade700),
                    const SizedBox(width: 3),
                    Text('사진',
                        style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          if (hasPhoto) const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(status).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _statusLabel(status),
              style: TextStyle(
                  color: _statusColor(status),
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showPhoto(String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('복약 인증 사진',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: photoUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(photoUrl.split(',').last),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : Image.network(photoUrl,
                        fit: BoxFit.cover, width: double.infinity),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
