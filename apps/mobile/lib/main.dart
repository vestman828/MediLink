import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'core/notification_service.dart';
import 'core/fcm_service.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/profile_screen.dart';
import 'features/home/home_screen.dart';

// 백그라운드 메시지 핸들러 (top-level 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class _DevHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      return host == '10.0.2.2' || host == 'localhost';
    };
    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    HttpOverrides.global = _DevHttpOverrides();
  }
  await initializeDateFormatting('ko', null);
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final token = await Storage.getToken();
  runApp(MediLinkApp(isLoggedIn: token != null));
}

class MediLinkApp extends StatefulWidget {
  final bool isLoggedIn;
  const MediLinkApp({super.key, required this.isLoggedIn});

  @override
  State<MediLinkApp> createState() => _MediLinkAppState();
}

class _MediLinkAppState extends State<MediLinkApp> {
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_servicesInitialized) return;
      _servicesInitialized = true;
      try {
        await NotificationService.init();
        // 로그인하지 않은 상태라면 이전 세션의 예약 알람을 모두 취소
        if (!widget.isLoggedIn) {
          await NotificationService.cancelAll();
        }
        await FcmService.init();
      } catch (e) {
        debugPrint('[BOOT] service init failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: widget.isLoggedIn ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/home': (_) => const HomeScreen(),
        '/profile': (_) => const ProfileScreen(),
      },
    );
  }
}
