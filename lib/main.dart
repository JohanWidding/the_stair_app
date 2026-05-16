import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/app_database.dart';
import 'database/level_repository.dart';
import 'database/project_repository.dart';
import 'database/sqlite_config.dart';
import 'screens/projects_screen.dart';
import 'services/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureSqliteIfNeeded();
  final appDb = await AppDatabase.open();
  final projectRepository = ProjectRepository(appDb);
  final levelRepository = LevelRepository(appDb);
  await projectRepository.load();
  final l10n = await AppLocalizations.create();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: l10n),
        ChangeNotifierProvider.value(value: projectRepository),
        ChangeNotifierProvider.value(value: levelRepository),
      ],
      child: const TheStairApp(),
    ),
  );
}

class TheStairApp extends StatelessWidget {
  const TheStairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Stair App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const ProjectsScreen(),
    );
  }
}
