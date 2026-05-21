import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class FamilyLinkScreen extends StatefulWidget {
  const FamilyLinkScreen({super.key});

  @override
  State<FamilyLinkScreen> createState() => _FamilyLinkScreenState();
}

class _FamilyLinkScreenState extends State<FamilyLinkScreen> {
  int? _guardianId;
  String? _token;
  List<dynamic> _patients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _guardianId = await Storage.getUserId();
    _token = await Storage.getToken();
    await _load();
  }

  Future<void> _load() async {
    if (_guardianId == null || _token == null) return;
    try {
      final res = await ApiClient.get('/family-map/$_guardianId/patients',
          token: _token);
      if (mounted) {
        setState(() {
          _patients = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAddDialog() {
    final phoneCtrl = TextEditingController();
    Map<String, dynamic>? foundPatient;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('가족 연동',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('환자 전화번호로 검색하세요',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [KoreanPhoneNumberFormatter()],
                    decoration: InputDecoration(
                      hintText: '010-0000-0000',
                      filled: true,
                      fillColor: AppTheme.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      final normalized = PhoneUtils.digitsOnly(phoneCtrl.text);
                      if (!PhoneUtils.isValidPhone(normalized)) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('전화번호 형식을 확인하세요'),
                                backgroundColor: Colors.red),
                          );
                        }
                        return;
                      }

                      try {
                        final res = await ApiClient.get(
                          '/family-map/search',
                          token: _token,
                          queryParams: {'phone': normalized},
                        );
                        setDialogState(() => foundPatient =
                            res['data'] as Map<String, dynamic>?);
                      } catch (e) {
                        setDialogState(() => foundPatient = null);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: const Text('검색'),
                  ),
                  if (foundPatient != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            foundPatient!['name'] as String? ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          Text(
                            foundPatient!['phone'] as String? ?? '',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final normalized =
                            PhoneUtils.digitsOnly(phoneCtrl.text);
                        Navigator.pop(ctx);
                        await _sendRequest(normalized);
                      },
                      child: const Text('연동 요청 보내기'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('취소'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendRequest(String phone) async {
    if (!PhoneUtils.isValidPhone(phone)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('전화번호 형식을 확인하세요'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    try {
      await ApiClient.post('/family-requests/send', {'phone': phone},
          token: _token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('연동 요청을 보냈습니다. 환자가 수락하면 연동됩니다.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('가족 연동'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('가족 추가'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _patients.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                            height: MediaQuery.of(context).size.height * 0.3),
                        const Column(
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: AppTheme.textSecondary),
                            SizedBox(height: 16),
                            Text('연동된 가족이 없어요',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 16)),
                            SizedBox(height: 8),
                            Text('아래 버튼으로 환자를 연동해보세요',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _patients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildCard(_patients[i]),
                    ),
            ),
    );
  }

  Future<void> _unlinkFamily(dynamic patient) async {
    final patientId = (patient['patient_id'] ?? patient['user_id']) as int;
    final patientName = patient['name'] as String? ?? '환자';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('연동 취소'),
        content:
            Text('$patientName님과의 연동을 취소하시겠어요?\n더 이상 복약 현황을 확인할 수 없게 됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('아니요')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('연동 취소'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiClient.delete('/family-map/patients/$patientId', token: _token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('연동을 해제했습니다.'), backgroundColor: Colors.orange),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildCard(dynamic patient) {
    return GestureDetector(
      onLongPress: () => _unlinkFamily(patient),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child:
                  const Icon(Icons.person, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient['name'] as String? ?? '',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  if (patient['phone'] != null)
                    Text(patient['phone'] as String,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('연동됨',
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
