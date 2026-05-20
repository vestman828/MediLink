import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';
import 'add_medicine_screen.dart';
import 'edit_medicine_screen.dart';
import 'drug_detail_screen.dart';

class MedicineListScreen extends StatefulWidget {
  final int? patientId;
  final String? patientName;
  final bool allowManage;

  const MedicineListScreen({
    super.key,
    this.patientId,
    this.patientName,
    this.allowManage = false,
  });

  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  int? _viewerId;
  int? _patientId;
  String? _role;
  String? _token;
  bool _readOnly = true;
  List<dynamic> _medicines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _viewerId = await Storage.getUserId();
    _role = await Storage.getUserRole();
    _token = await Storage.getToken();
    _patientId = widget.patientId ?? _viewerId;
    _readOnly = !(widget.allowManage && _role == 'guardian');
    await _load();
  }

  Future<void> _load() async {
    if (_patientId == null || _token == null) return;
    setState(() => _loading = true);

    try {
      final res =
          await ApiClient.get('/patient-medicines/$_patientId', token: _token);
      if (mounted) {
        setState(() {
          _medicines = res['data'] as List<dynamic>? ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showOptions(dynamic med) async {
    final pmId = med['patient_medicine_id'] as int;
    final name = med['name'] as String? ?? '약';
    final isActive = (med['is_active'] as num? ?? 1) == 1;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            if (isActive)
              ListTile(
                leading:
                    const Icon(Icons.edit_outlined, color: AppTheme.primary),
                title: const Text('스케줄 수정'),
                subtitle: const Text('복약 시간대와 용량을 변경합니다'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMedicine(med);
                },
              ),
            if (isActive)
              ListTile(
                leading: const Icon(Icons.pause_circle_outline,
                    color: Colors.orange),
                title: const Text('복용 중단'),
                subtitle: const Text('기록은 유지하고 복용만 중단합니다'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeactivate(pmId, name);
                },
              )
            else
              ListTile(
                leading:
                    const Icon(Icons.play_circle_outline, color: Colors.green),
                title:
                    const Text('복용 재개', style: TextStyle(color: Colors.green)),
                subtitle: const Text('복용을 다시 시작합니다'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmReactivate(pmId, name);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('완전 삭제', style: TextStyle(color: Colors.red)),
              subtitle: const Text('스케줄 및 기록까지 삭제되며 복구할 수 없습니다'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(pmId, name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _safeInfoValue(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? '-' : text;
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMedicineInfo(dynamic med) async {
    final name = (med['name'] ?? '').toString().trim();
    Map<String, dynamic> detail = {'name': name};

    if (name.isNotEmpty && _token != null) {
      try {
        final res = await ApiClient.get(
          '/medicines/detail',
          token: _token,
          queryParams: {'name': name},
        );
        final data = res['data'] as Map<String, dynamic>?;
        if (data != null) detail = data;
      } catch (_) {
        // Fallback to "-" output below when API/DB detail lookup fails.
      }
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _safeInfoValue(detail['name']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _infoRow('제조사', _safeInfoValue(detail['entpName'])),
                _infoRow('효능·효과', _safeInfoValue(detail['efcy'])),
                _infoRow('사용법', _safeInfoValue(detail['useMethod'])),
                _infoRow('주의사항(경고)', _safeInfoValue(detail['atpnWarn'])),
                _infoRow('주의사항', _safeInfoValue(detail['atpn'])),
                _infoRow('상호작용', _safeInfoValue(detail['intrc'])),
                _infoRow('부작용', _safeInfoValue(detail['se'])),
                _infoRow('보관법', _safeInfoValue(detail['deposit'])),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editMedicine(dynamic med) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditMedicineScreen(
          patientMedicineId: med['patient_medicine_id'] as int,
          medicineName: med['name'] as String? ?? '',
          currentDose: med['dose'] as String? ?? '',
        ),
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _confirmReactivate(int pmId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('복용 재개'),
        content: Text('$name 복용을 다시 시작할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('재개'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.patch('/patient-medicines/$pmId/reactivate',
          token: _token);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('복용을 재개했습니다.'), backgroundColor: Colors.green),
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

  Future<void> _confirmDeactivate(int pmId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('복용 중단'),
        content: Text('$name 복용을 중단할까요?\n기록은 유지됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('중단'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.patch('/patient-medicines/$pmId/deactivate',
          token: _token);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('복용을 중단했습니다.'), backgroundColor: Colors.orange),
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

  Future<void> _confirmDelete(int pmId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('약 삭제'),
        content: Text('$name을(를) 완전히 삭제할까요?\n스케줄과 복약 기록이 모두 삭제됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiClient.delete('/patient-medicines/$pmId', token: _token);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('약을 삭제했습니다.'), backgroundColor: Colors.red),
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
        title: Text(
          widget.patientName == null
              ? (_readOnly ? '내 약' : '약 관리')
              : '${widget.patientName}님 약 관리',
        ),
        automaticallyImplyLeading: widget.patientId != null,
      ),
      floatingActionButton: _readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddMedicineScreen(
                      patientId: _patientId,
                      patientName: widget.patientName,
                    ),
                  ),
                );
                _load();
              },
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('약 추가'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _medicines.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                            height: MediaQuery.of(context).size.height * 0.3),
                        const Column(
                          children: [
                            Icon(Icons.medication_outlined,
                                size: 64, color: AppTheme.textSecondary),
                            SizedBox(height: 16),
                            Text('등록된 약이 없어요',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 16)),
                          ],
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      itemCount: _medicines.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _buildCard(_medicines[i]),
                    ),
            ),
    );
  }

  Widget _buildCard(dynamic med) {
    final isActive = (med['is_active'] as num? ?? 1) == 1;
    final iconColor = isActive ? AppTheme.primary : Colors.grey;
    final bgColor = isActive
        ? AppTheme.primary.withOpacity(0.1)
        : Colors.grey.withOpacity(0.1);

    return GestureDetector(
      onTap: () {
        final name = med['name'] as String? ?? '';
        if (name.isNotEmpty) {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DrugDetailScreen(medicineName: name)));
        }
      },
      onLongPress: () => _showMedicineInfo(med),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: isActive ? null : Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.medication, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med['name'] as String? ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isActive ? null : Colors.grey,
                        decoration:
                            isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${med['dose']}  |  ${med['unit'] ?? 'mg'}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    if (med['frequency'] != null)
                      Text(
                        med['frequency'] as String,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive ? '복용중' : '중단됨',
                      style: TextStyle(
                        color: isActive ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!_readOnly)
                    InkWell(
                      onTap: () => _showOptions(med),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '관리',
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (!_readOnly) const SizedBox(height: 4),
                  Text(
                    _readOnly ? '복약 시간은 보호자가 설정합니다' : '길게 눌러 약 정보',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
