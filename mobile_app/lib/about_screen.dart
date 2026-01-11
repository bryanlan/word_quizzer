import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String appName = 'Vocab Master';
  String version = 'Unknown';
  String buildNumber = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appName = info.appName.isEmpty ? appName : info.appName;
      version = info.version.isEmpty ? version : info.version;
      buildNumber = info.buildNumber;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_version', version);
      await prefs.setString('app_build_number', buildNumber);
    } catch (_) {
      // Keep defaults if version lookup fails.
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    buildNumber.isEmpty ? 'Version $version' : 'Version $version+$buildNumber',
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Word Quizzer helps you master vocabulary with daily quizzes, context, and spaced review.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
    );
  }
}

