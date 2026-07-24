import 'package:flutter/material.dart';

void main() => runApp(const ChoreApp());

/// Root widget of the chore app.
///
/// Currently a placeholder shell; real navigation lands with the first
/// feature screens.
class ChoreApp extends StatelessWidget {
  /// Creates the root widget.
  const ChoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chores',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const Scaffold(
        body: Center(child: Text('Chores — coming soon')),
      ),
    );
  }
}
