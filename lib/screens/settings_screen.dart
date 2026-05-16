import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../services/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _resetDatabase(BuildContext context, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('settings_reset_db_title')),
        content: Text(l10n.tr('settings_reset_db_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('settings_reset_db_confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppDatabase.deleteFile();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<AppLocalizations>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('settings_title')),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Language ───────────────────────────────────────────────────────
          _SectionHeader(label: l10n.tr('settings_language')),
          const SizedBox(height: 8),
          _LanguagePicker(l10n: l10n),
          const SizedBox(height: 24),

          // ── Units (TBA) ────────────────────────────────────────────────────
          _SectionHeader(label: l10n.tr('settings_units')),
          const SizedBox(height: 8),
          Opacity(
            opacity: 0.38,
            child: _TbaListTile(
              icon: Icons.straighten_outlined,
              label: l10n.tr('settings_units'),
              subtitle: l10n.tr('settings_units_subtitle'),
            ),
          ),
          const SizedBox(height: 32),

          // ── Developer ──────────────────────────────────────────────────────
          const Divider(),
          const SizedBox(height: 16),
          _SectionHeader(label: l10n.tr('settings_developer')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text(l10n.tr('settings_reset_db')),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              side: BorderSide(color: colorScheme.error),
            ),
            onPressed: () => _resetDatabase(context, l10n),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.l10n});
  final AppLocalizations l10n;

  static const _labelKeys = {'en': 'lang_english', 'no': 'lang_norwegian'};

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return RadioGroup<String>(
      groupValue: l10n.locale,
      onChanged: (code) {
        if (code != null) context.read<AppLocalizations>().setLocale(code);
      },
      child: Column(
        children: AppLocalizations.supportedLocales.entries.map((entry) {
          final isSelected = l10n.locale == entry.key;
          return RadioListTile<String>(
            dense: true,
            title: Text(l10n.tr(_labelKeys[entry.key]!)),
            value: entry.key,
            secondary: isSelected
                ? Icon(Icons.check_circle, color: primary, size: 20)
                : const SizedBox(width: 20),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _TbaListTile extends StatelessWidget {
  const _TbaListTile({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  final IconData icon;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Chip(label: Text('TBA')),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      onTap: null,
    );
  }
}
