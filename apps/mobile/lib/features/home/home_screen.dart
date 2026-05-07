import 'package:flutter/material.dart';
import '../../core/storage.dart';
import '../patient/patient_main_screen.dart';
import '../guardian/guardian_main_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final role = await Storage.getUserRole();
    if (mounted) setState(() { _role = role; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_role == 'guardian') {
      return const GuardianMainScreen();
    }
    return const PatientMainScreen();
  }
}
