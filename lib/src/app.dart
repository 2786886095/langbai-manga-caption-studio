import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'project_hub_screen.dart';

class BubbleCaptionApp extends StatelessWidget {
  const BubbleCaptionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '浪白漫画字幕工坊',
      theme: buildAppTheme(),
      home: const ProjectHubScreen(),
    );
  }
}
