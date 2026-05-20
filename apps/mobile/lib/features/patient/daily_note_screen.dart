import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../data/api_client.dart';

class DailyNoteScreen extends StatefulWidget {
  final DateTime date;
  const DailyNoteScreen({super.key, required this.date});

  @override
  State<DailyNoteScreen> createState() => _DailyNoteScreenState();
}

class _DailyNoteScreenState extends State<DailyNoteScreen> {
  String? _token;
  int _conditionScore = 3;
  final _memoCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  final _conditionEmojis = ['😞', '😕', '😐', '🙂', '😊'];
  final _conditionLabels = ['많이 나빠요', '조금 나빠요', '보통이에요', '좋아요', '아주 좋아요'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _token = await Storage.getToken();
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
      final res = await ApiClient.get('/daily-notes', token: _token, queryParams: {'date': dateStr});
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null && mounted) {
        setState(() {
          _conditionScore = (data['condition_score'] as num?)?.toInt() ?? 3;
          _memoCtrl.text = data['memo'] as String? ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
      await ApiClient.post('/daily-notes', {
        'note_date': dateStr,
        'condition_score': _conditionScore,
        'memo': _memoCtrl.text.trim(),
      }, token: _token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('M월 d일 (E)', 'ko').format(widget.date);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text('$dateStr 메모')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 컨디션 점수
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('오늘 컨디션은 어떠세요?',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(5, (i) {
                            final score = i + 1;
                            final selected = _conditionScore == score;
                            return GestureDetector(
                              onTap: () => setState(() => _conditionScore = score),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: selected ? AppTheme.primary.withOpacity(0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  border: selected ? Border.all(color: AppTheme.primary, width: 2) : null,
                                ),
                                child: Column(
                                  children: [
                                    Text(_conditionEmojis[i], style: TextStyle(fontSize: selected ? 32 : 26)),
                                    const SizedBox(height: 4),
                                    Text('$score점',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                                          color: selected ? AppTheme.primary : AppTheme.textSecondary,
                                        )),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _conditionLabels[_conditionScore - 1],
                            style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 메모
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('메모 (부작용, 특이사항 등)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _memoCtrl,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: '예) 두통이 있었어요, 속이 조금 불편했어요...',
                            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
