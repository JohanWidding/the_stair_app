import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppLocalizations extends ChangeNotifier {
  static const defaultLocale = 'en';

  static const supportedLocales = <String, String>{
    'en': 'English',
    'no': 'Norwegian',
  };

  String _locale;
  Map<String, String> _strings = {};

  AppLocalizations._({required String locale}) : _locale = locale;

  String get locale => _locale;

  String tr(String key) => _strings[key] ?? key;

  static Future<AppLocalizations> create() async {
    final locale = await _readLocale() ?? defaultLocale;
    final instance = AppLocalizations._(locale: locale);
    await instance._load(locale);
    return instance;
  }

  Future<void> setLocale(String code) async {
    if (!supportedLocales.containsKey(code) || code == _locale) return;
    await _load(code);
    _locale = code;
    await _writeLocale(code);
    notifyListeners();
  }

  Future<void> _load(String code) async {
    try {
      final raw = await rootBundle.loadString('assets/lang/$code.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      _strings = map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      if (code != defaultLocale) await _load(defaultLocale);
    }
  }

  static Future<File> _settingsFile() async {
    final dir = await getDatabasesPath();
    return File(p.join(dir, 'settings.json'));
  }

  static Future<String?> _readLocale() async {
    try {
      final file = await _settingsFile();
      if (!await file.exists()) return null;
      final map = json.decode(await file.readAsString()) as Map<String, dynamic>;
      final v = map['locale'];
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeLocale(String code) async {
    try {
      final file = await _settingsFile();
      final existing = await file.exists()
          ? (json.decode(await file.readAsString()) as Map<String, dynamic>)
          : <String, dynamic>{};
      existing['locale'] = code;
      await file.writeAsString(json.encode(existing));
    } catch (_) {}
  }
}
