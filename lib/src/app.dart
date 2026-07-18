import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_theme.dart';
import 'app_localization.dart';
import 'project_hub_screen.dart';
import 'platform_window_title.dart';

class BubbleCaptionApp extends StatefulWidget {
  const BubbleCaptionApp({super.key});

  @override
  State<BubbleCaptionApp> createState() => _BubbleCaptionAppState();
}

class _BubbleCaptionAppState extends State<BubbleCaptionApp> {
  @override
  void initState() {
    super.initState();
    AppLocaleController.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppLocaleController.instance,
      builder: (context, _) {
        final title = tr('浪白漫画字幕工坊');
        setPlatformWindowTitle(title);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: title,
          theme: buildAppTheme(),
          locale: AppLocaleController.instance.locale,
          supportedLocales: AppLocaleController.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const ProjectHubScreen(),
        );
      },
    );
  }
}
