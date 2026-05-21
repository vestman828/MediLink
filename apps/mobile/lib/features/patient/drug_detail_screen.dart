import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class DrugDetailScreen extends StatefulWidget {
  final String medicineName;
  const DrugDetailScreen({super.key, required this.medicineName});

  @override
  State<DrugDetailScreen> createState() => _DrugDetailScreenState();
}

class _DrugDetailScreenState extends State<DrugDetailScreen> {
  String? _token;
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _token = await Storage.getToken();
    try {
      final res = await ApiClient.get(
        '/medicines/detail',
        token: _token,
        queryParams: {'name': widget.medicineName},
      );
      if (mounted) {
        setState(() {
          _detail = res['data'] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(widget.medicineName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? const Center(
                  child: Text('약 정보를 찾을 수 없어요',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 약 이름 + 제조사
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.medication,
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _detail!['name'] as String? ?? widget.medicineName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if ((_detail!['entpName'] as String?)?.trim().isNotEmpty == true &&
                              (_detail!['entpName'] as String).trim() != '-') ...[
                            const SizedBox(height: 6),
                            Text(
                              _detail!['entpName'] as String,
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSection('약 설명', _detail!['efcy'] as String?),
                    const SizedBox(height: 20),
                    Text(
                      '※ 본 정보는 식품의약품안전처 e약은요 서비스 기반입니다.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
    );
  }

  Widget _buildSection(String title, String? content, {Color? color, Color? borderColor}) {
    if (content == null || content.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(content.trim(),
              style: const TextStyle(fontSize: 13, height: 1.6, color: Colors.black87)),
        ],
      ),
    );
  }
}
