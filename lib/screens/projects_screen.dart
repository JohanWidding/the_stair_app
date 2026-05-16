import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/project_repository.dart';
import '../models/project.dart';
import '../services/app_localizations.dart';
import 'project_portfolio_screen.dart';
import 'settings_screen.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppLocalizations>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('projects_title')),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.tr('tooltip_settings'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Selector<ProjectRepository, List<Project>>(
        selector: (_, repo) => repo.projects,
        builder: (context, projects, _) {
          if (projects.isEmpty) {
            return Center(
              child: Text(l10n.tr('projects_empty')),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final p = projects[index];
              return _ProjectCard(project: p);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createProject(context),
        tooltip: l10n.tr('tooltip_new_project'),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _createProject(BuildContext context) async {
    final name = await _showNameDialog(context, title: 'New Project', hint: 'Project name');
    if (name == null || !context.mounted) return;
    final repo = context.read<ProjectRepository>();
    final id = await repo.insert(name);
    if (id != null && context.mounted) {
      final project = repo.byId(id);
      if (project != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProjectPortfolioScreen(project: project)),
        );
      }
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.stairs, size: 28),
        title: Text(project.name),
        subtitle: Text(
          _formatDate(project.createdAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _onMenu(context, v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProjectPortfolioScreen(project: project)),
        ),
      ),
    );
  }

  Future<void> _onMenu(BuildContext context, String action) async {
    final repo = context.read<ProjectRepository>();
    if (action == 'rename') {
      final name = await _showNameDialog(context,
          title: 'Rename', hint: 'New name', initial: project.name);
      if (name != null) await repo.rename(project.id, name);
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete project?'),
          content: Text('Delete "${project.name}"? This cannot be undone.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) await repo.delete(project.id);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

Future<String?> _showNameDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () {
              final v = ctrl.text.trim();
              Navigator.pop(ctx, v.isEmpty ? null : v);
            },
            child: const Text('OK')),
      ],
    ),
  );
}
