import 'package:flutter/material.dart';

import 'word_editor_screen.dart';

class WordEditorPagerScreen extends StatefulWidget {
  final List<int> wordIds;
  final int initialIndex;

  const WordEditorPagerScreen({
    super.key,
    required this.wordIds,
    required this.initialIndex,
  });

  @override
  State<WordEditorPagerScreen> createState() => _WordEditorPagerScreenState();
}

class _WordEditorPagerScreenState extends State<WordEditorPagerScreen> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.wordIds.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.wordIds.length - 1);
    _controller = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.wordIds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Word Editor')),
        body: const Center(child: Text('No words found for this filter.')),
      );
    }

    return PageView.builder(
      controller: _controller,
      itemCount: widget.wordIds.length,
      itemBuilder: (context, index) {
        return WordEditorScreen(wordId: widget.wordIds[index]);
      },
    );
  }
}
