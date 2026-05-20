import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';

class FamilyRequestScreen extends StatefulWidget {
  final List<dynamic> requests;
  final String token;
  const FamilyRequestScreen({super.key, required this.requests, required this.token});

  @override
  State<FamilyRequestScreen> createState() => _FamilyRequestScreenState();
}

class _FamilyRequestScreenState extends State<FamilyRequestScreen> {
  late List<dynamic> _requests;
  final Set<int> _processing = {};

  @override
  void initState() {
    super.initState();
    _requests = List.from(widget.requests);
  }

  Future<void> _respond(int requestId, String action) async {
    setState(() => _processing.add(requestId));
    try {
      await ApiClient.post(
        '/family-requests/respond',
        {'request_id': requestId, 'action': action},
        token: widget.token,
      );
      setState(() {
        _requests.removeWhere((r) => r['request_id'] == requestId);
        _processing.remove(requestId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(action == 'accept' ? '보호자 연동을 수락했습니다.' : '보호자 연동을 거절했습니다.'),
          backgroundColor: action == 'accept' ? Colors.green : Colors.red,
        ));
      }
      if (_requests.isEmpty && mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _processing.remove(requestId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('보호자 연동 요청')),
      body: _requests.isEmpty
          ? const Center(child: Text('요청이 없습니다.'))
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _requests.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final req = _requests[i];
                final reqId = req['request_id'] as int;
                final isProcessing = _processing.contains(reqId);
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req['guardian_name'] as String? ?? '알 수 없음',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  req['guardian_phone'] as String? ?? '',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '이 분이 나의 보호자로 복약 현황을 확인할 수 있게 됩니다.',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isProcessing ? null : () => _respond(reqId, 'reject'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: BorderSide(color: Colors.red.shade200),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('거절'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isProcessing ? null : () => _respond(reqId, 'accept'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: isProcessing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('수락'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
