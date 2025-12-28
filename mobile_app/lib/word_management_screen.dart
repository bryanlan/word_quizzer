import 'package:flutter/material.dart';

class WordManagementScreen extends StatelessWidget {
  const WordManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Word Management')),
      body: const Center(
        child: Text(
          'Word management is coming next.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
