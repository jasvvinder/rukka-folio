// A root placeholder: title bar + one line. Ships so the shell runs before the
// feature lanes land; each feature replaces its root via `buildRouter`.
import 'package:flutter/material.dart';

import '../tokens.dart';

/// Title + body, nothing else.
class RkPlaceholderScreen extends StatelessWidget {
  const RkPlaceholderScreen({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: Text(body, style: text.bodyLarge),
        ),
      ),
    );
  }
}
