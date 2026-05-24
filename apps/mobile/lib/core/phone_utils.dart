import 'package:flutter/services.dart';

class PhoneUtils {
  static String digitsOnly(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static bool isValidPhone(String input) {
    final digits = digitsOnly(input);
    return RegExp(r'^(01[016789]\d{7,8}|0\d{8,10})$').hasMatch(digits);
  }

  static String formatPhone(String input) {
    final digits = digitsOnly(input);
    if (digits.isEmpty) return '';

    if (digits.length < 4) {
      return digits;
    }

    if (digits.startsWith('02')) {
      if (digits.length <= 2) return digits;
      if (digits.length <= 6) {
        return '${digits.substring(0, 2)}-${digits.substring(2)}';
      }
      if (digits.length <= 10) {
        return '${digits.substring(0, 2)}-${digits.substring(2, digits.length - 4)}-${digits.substring(digits.length - 4)}';
      }
      return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6, 10)}';
    }

    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    if (digits.length <= 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, digits.length - 4)}-${digits.substring(digits.length - 4)}';
    }
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, 11)}';
  }
}

class KoreanPhoneNumberFormatter extends TextInputFormatter {
  const KoreanPhoneNumberFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = PhoneUtils.digitsOnly(newValue.text);
    final capped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final formatted = PhoneUtils.formatPhone(capped);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
