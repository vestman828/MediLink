import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'core/notification_service.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/profile_screen.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko', null);
  await NotificationService.init();
  final token = await Storage.getToken();
  runApp(MediLinkApp(isLoggedIn: token != null));
}

class MediLinkApp extends StatelessWidget {
  final bool isLoggedIn;
  const MediLinkApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/home': (_) => const HomeScreen(),
        '/profile': (_) => const ProfileScreen(),
      },
    );
  }
}
