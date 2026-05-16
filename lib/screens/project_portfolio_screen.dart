import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/level_repository.dart';
import '../models/project.dart';
import 'editor_screen.dart';

class ProjectPortfolioScreen extends StatefulWidget {
  const ProjectPortfolioScreen({super.key, required this.project});

  final Project project;

  @override
  State<ProjectPortfolioScreen> createState() => _ProjectPortfolioScreenState();
}

class _ProjectPortfolioScreenState extends State<ProjectPortfolioScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final levelRepo = context.read<LevelRepository>();
    await levelRepo.ensureDefaultLevel(widget.project.id);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _PortfolioGrid(project: widget.project),
    );
  }
}

class _PortfolioGrid extends StatelessWidget {
  const _PortfolioGrid({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 0.88,
      children: [
        _PortfolioTile(
          icon: Icons.architecture,
          title: 'Staircase\nEditor',
          subtitle: 'Design and fit\nyour staircase',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditorScreen(project: project),
            ),
          ),
        ),
        _PortfolioTile(
          icon: Icons.view_in_ar,
          title: '3D View',
          subtitle: 'Inspect the staircase\nin 3D',
          enabled: false,
          badge: 'TBA',
          onTap: null,
        ),
        _PortfolioTile(
          icon: Icons.list_alt_outlined,
          title: 'Cut List',
          subtitle: 'Measurements\n& material report',
          enabled: false,
          badge: 'TBA',
          onTap: null,
        ),
        _PortfolioTile(
          icon: Icons.picture_as_pdf_outlined,
          title: 'PDF Export',
          subtitle: 'Export project\nas PDF',
          enabled: false,
          badge: 'TBA',
          onTap: null,
        ),
      ],
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor    = enabled ? cs.primary : cs.onSurfaceVariant;
    final containerColor = enabled ? cs.primaryContainer : cs.surfaceContainerHighest;
    final iconColor      = enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: enabled ? 1 : 0,
      color: enabled ? cs.surface : cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: enabled
              ? cs.outlineVariant
              : cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: containerColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 28),
                  ),
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: activeColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
