import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/phone_utils.dart';
import '../../core/theme.dart';
import '../../data/api_client.dart';
import '../../data/auth_repository.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _repo = AuthRepository();

  String _role = 'patient';
  bool _loading = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _otpSent = false;
  bool _phoneVerified = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  String? _verifyToken;
  String? _verifiedPhone;
  String? _debugCode;

  String get _normalizedPhone => PhoneUtils.digitsOnly(_phoneCtrl.text);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocusNode.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _resetPhoneVerification() {
    _otpCtrl.clear();
    _otpSent = false;
    _phoneVerified = false;
    _verifyToken = null;
    _verifiedPhone = null;
    _debugCode = null;
  }

  Future<void> _sendOtp() async {
    final normalized = _normalizedPhone;
    if (!PhoneUtils.isValidPhone(normalized)) {
      _showError('전화번호 형식을 확인해주세요.');
      return;
    }

    setState(() {
      _sendingOtp = true;
      _phoneVerified = false;
      _verifyToken = null;
      _verifiedPhone = null;
    });

    try {
      final result = await _repo.sendSignupOtp(phone: normalized);
      if (!mounted) return;

      setState(() {
        _otpSent = true;
        _debugCode = result.debugCode;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_otpSent) return;
        _otpFocusNode.requestFocus();
      });

      final message = result.debugCode != null
          ? '인증번호를 전송했습니다. (개발용 코드: ${result.debugCode})'
          : '인증번호를 전송했습니다.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('인증번호 전송에 실패했습니다.');
    } finally {
      if (mounted) {
        setState(() => _sendingOtp = false);
      }
    }
  }

  Future<void> _verifyOtp() async {
    final normalized = _normalizedPhone;
    final code = _otpCtrl.text.trim();

    if (!PhoneUtils.isValidPhone(normalized)) {
      _showError('전화번호 형식을 확인해주세요.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showError('인증번호 6자리를 입력해주세요.');
      return;
    }

    setState(() => _verifyingOtp = true);

    try {
      final token = await _repo.verifySignupOtp(phone: normalized, code: code);
      if (!mounted) return;

      setState(() {
        _phoneVerified = true;
        _verifyToken = token;
        _verifiedPhone = normalized;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('전화번호 인증이 완료되었습니다.'),
          backgroundColor: Colors.green,
        ),
      );
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('인증번호 확인에 실패했습니다.');
    } finally {
      if (mounted) {
        setState(() => _verifyingOtp = false);
      }
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    final normalizedPhone = _normalizedPhone;
    if (!_phoneVerified ||
        _verifyToken == null ||
        _verifiedPhone != normalizedPhone) {
      _showError('전화번호 인증을 먼저 완료해주세요.');
      return;
    }

    setState(() => _loading = true);

    try {
      await _repo.signup(
        name: _nameCtrl.text.trim(),
        phone: normalizedPhone,
        password: _passwordCtrl.text,
        role: _role,
        verifyToken: _verifyToken!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원가입이 완료되었습니다. 로그인해주세요.'),
          backgroundColor: AppTheme.primary,
        ),
      );
      Navigator.pop(context);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('서버에 연결할 수 없습니다.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MediLink 계정을 만들어보세요',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '계속하려면 전화번호 인증이 필요합니다.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    hintText: '이름을 입력하세요',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '이름을 입력해주세요.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: const [KoreanPhoneNumberFormatter()],
                  onChanged: (_) {
                    final current = _normalizedPhone;
                    if (_verifiedPhone != null && current != _verifiedPhone) {
                      setState(_resetPhoneVerification);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '전화번호',
                    hintText: '010-1234-5678',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    suffixIcon: TextButton(
                      onPressed: _sendingOtp ? null : _sendOtp,
                      child: _sendingOtp
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_otpSent ? '재전송' : '인증요청'),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return '전화번호를 입력해주세요.';
                    }
                    if (!PhoneUtils.isValidPhone(v)) {
                      return '전화번호 형식이 올바르지 않습니다.';
                    }
                    return null;
                  },
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          focusNode: _otpFocusNode,
                          controller: _otpCtrl,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          autocorrect: false,
                          enableSuggestions: false,
                          buildCounter: (
                            BuildContext context, {
                            required int currentLength,
                            required bool isFocused,
                            required int? maxLength,
                          }) =>
                              null,
                          decoration: const InputDecoration(
                            labelText: '인증번호',
                            hintText: '6자리를 입력하세요',
                            prefixIcon: Icon(Icons.verified_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 92,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(92, 48),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _verifyingOtp ? null : _verifyOtp,
                          child: _verifyingOtp
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('확인'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_phoneVerified)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '전화번호 인증 완료',
                      style: TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ),
                if (_debugCode != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '개발용 OTP: $_debugCode',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '비밀번호를 입력해주세요.';
                    if (v.length < 6) return '비밀번호는 6자 이상이어야 합니다.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '비밀번호 확인',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscureConfirm = !_obscureConfirm,
                      ),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '비밀번호를 다시 입력해주세요.';
                    if (v != _passwordCtrl.text) return '비밀번호가 일치하지 않습니다.';
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                const Text(
                  '역할 선택',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RoleCard(
                        label: '환자',
                        icon: Icons.elderly,
                        subtitle: '복약 기록을 관리합니다',
                        selected: _role == 'patient',
                        onTap: () => setState(() => _role = 'patient'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RoleCard(
                        label: '보호자',
                        icon: Icons.favorite_outline,
                        subtitle: '환자 상태를 확인합니다',
                        selected: _role == 'guardian',
                        onTap: () => setState(() => _role = 'guardian'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _loading ? null : _signup,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('회원가입'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.primary.withOpacity(0.08) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
