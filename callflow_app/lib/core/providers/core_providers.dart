import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'
    show StateNotifier, StateNotifierProvider;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../database/app_database.dart';
import '../native/native_bridge.dart';
import '../network/api_client.dart';
import '../network/auth_interceptor.dart';

// --- Auth state ---

final authStateProvider = FutureProvider<bool>((ref) async {
  return AuthInterceptor.hasTokens();
});

// --- User ---

final currentUserProvider = StreamProvider<User?>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.users).watchSingleOrNull();
});

// --- Service running state ---

final serviceRunningProvider =
    StateNotifierProvider<ServiceRunningNotifier, bool>((ref) {
  return ServiceRunningNotifier(ref.watch(nativeBridgeProvider));
});

class ServiceRunningNotifier extends StateNotifier<bool> {
  final NativeBridge _bridge;

  ServiceRunningNotifier(this._bridge) : super(false) {
    _checkState();
  }

  Future<void> _checkState() async {
    try {
      state = await _bridge.isServiceRunning();
    } catch (_) {}
  }

  Future<void> toggle() async {
    try {
      if (state) {
        await _bridge.stopCallDetection();
      } else {
        await _bridge.startCallDetection();
      }
      state = !state;
    } catch (_) {}
  }

  Future<void> start() async {
    try {
      await _bridge.startCallDetection();
      state = true;
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _bridge.stopCallDetection();
      state = false;
    } catch (_) {}
  }
}

// --- Stats ---

final callsTodayProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchEventsTodayCount();
});

final smsSentTodayProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchMessagesByChannelCount('sms');
});

final successRateProvider = StreamProvider<double>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSuccessRate();
});

// --- Call events stream listener ---

final callEventListenerProvider = Provider<void>((ref) {
  final bridge = ref.watch(nativeBridgeProvider);
  final db = ref.watch(databaseProvider);

  var eventQueue = Future<void>.value();
  final subscription = bridge.callEventStream.listen((event) {
    eventQueue = eventQueue
        .then((_) => _handleNativeEvent(db, event))
        .catchError((_) {});
  });

  ref.onDispose(subscription.cancel);
});

Future<void> _handleNativeEvent(
  AppDatabase db,
  Map<String, dynamic> event,
) async {
  final type = event['type']?.toString();

  if (type == 'call_event') {
    await db.insertCallEvent(CallEventsCompanion.insert(
      eventId: event['event_id'] as String? ?? '',
      phone: event['phone'] as String? ?? '',
      contactName: Value(event['contact_name'] as String? ?? ''),
      direction: event['direction'] as String? ?? '',
      durationSeconds: Value(_toInt(event['duration_seconds']) ?? 0),
      callTimestamp: DateTime.fromMillisecondsSinceEpoch(
        _toInt(event['call_timestamp']) ?? 0,
      ),
    ));
    return;
  }

  if (type == 'message_log') {
    final payload = event['data'] is Map
        ? Map<String, dynamic>.from(event['data'] as Map)
        : event;

    final eventId = payload['event_id']?.toString() ?? '';
    final callEvent = await _resolveCallEventForMessageLog(db, eventId);
    if (callEvent == null) return;

    final normalizedChannel =
        (payload['channel']?.toString().trim().toLowerCase().isNotEmpty ??
                false)
            ? payload['channel']?.toString().trim().toLowerCase()
            : 'sms';

    await db.insertMessageLog(MessageLogsCompanion.insert(
      callEventId: callEvent.id,
      channel: normalizedChannel!,
      status: payload['status']?.toString() ?? '',
      sendMethod: Value(payload['send_method']?.toString() ?? ''),
      simSlot: Value(_toInt(payload['sim_slot'])),
      smsParts: Value(_toInt(payload['sms_parts'])),
      errorMessage: Value(payload['error_message']?.toString() ?? ''),
      sentAt: Value(_toDateTimeFromMillis(payload['sent_at'])),
    ));
  }
}

Future<CallEvent?> _resolveCallEventForMessageLog(
  AppDatabase db,
  String eventId,
) async {
  if (eventId.isNotEmpty) {
    for (var i = 0; i < 5; i++) {
      final matches = await (db.select(db.callEvents)
            ..where((e) => e.eventId.equals(eventId))
            ..limit(1))
          .get();
      if (matches.isNotEmpty) return matches.first;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
  return (await db.getCallEvents(limit: 1)).firstOrNull;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _toDateTimeFromMillis(dynamic value) {
  final millis = _toInt(value);
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

// --- Sync ---

final syncProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(apiClientProvider),
    ref.watch(databaseProvider),
    ref.watch(nativeBridgeProvider),
  );
});

class SyncService {
  final ApiClient _api;
  final AppDatabase _db;
  final NativeBridge _bridge;

  SyncService(this._api, this._db, this._bridge);

  Future<void> pullConfig() async {
    try {
      final response = await _api.get('/sync/config');
      final data = response.data['data'] as Map<String, dynamic>?;
      if (data == null) return;

      // Update user
      final userData = data['user'] as Map<String, dynamic>?;
      if (userData != null) {
        await _db.upsertUser(UsersCompanion(
          id: Value(userData['id'] as int),
          phone: Value(userData['phone'] as String? ?? ''),
          businessName: Value(userData['business_name'] as String? ?? ''),
          plan: Value(userData['plan'] as String? ?? 'none'),
          planStartedAt: Value(userData['plan_started_at'] != null
              ? DateTime.parse(userData['plan_started_at'] as String)
              : null),
          planExpiresAt: Value(userData['plan_expires_at'] != null
              ? DateTime.parse(userData['plan_expires_at'] as String)
              : null),
          status: Value(userData['status'] as String? ?? 'active'),
        ));
      }

      // Update server templates
      final templatesData = data['templates'] as List<dynamic>?;
      if (templatesData != null) {
        final serverTemplates = templatesData.map((t) {
          final tmpl = t as Map<String, dynamic>;
          return TemplatesCompanion.insert(
            serverId: Value(tmpl['id'] as int?),
            name: tmpl['name'] as String? ?? '',
            body: tmpl['body'] as String? ?? '',
            type: tmpl['type'] as String? ?? 'outgoing',
            channel: tmpl['channel'] as String? ?? 'both',
            imagePath: Value(tmpl['image_url'] as String?),
            language: Value(tmpl['language'] as String? ?? 'en'),
            isDefault: Value(tmpl['is_default'] as bool? ?? false),
            source: const Value('server'),
            isSynced: const Value(true),
          );
        }).toList();
        await _db.replaceServerTemplates(serverTemplates);
      }

      // Update rules
      final rulesData = data['rules'];
      if (rulesData != null) {
        final rulesJson = jsonEncode(rulesData);
        await _db.upsertRule(RulesCompanion(
          configJson: Value(rulesJson),
          isSynced: const Value(true),
        ));
      }
    } catch (e) {
      rethrow;
    } finally {
      // Always push local config to native, even if sync failed
      await _pushRuleConfigToNative();
    }
  }

  /// Push unique contacts (name + phone from call events) to backend.
  /// Called periodically (weekly) — optional background sync.
  Future<void> pushContacts() async {
    try {
      final events = await _db.getUnsyncedEvents(limit: 500);
      if (events.isEmpty) return;

      // Deduplicate by phone number, keep latest name
      final contactMap = <String, String?>{};
      for (final event in events) {
        contactMap[event.phone] = event.contactName;
      }

      final contacts = contactMap.entries
          .map((e) => {'phone': e.key, 'name': e.value ?? ''})
          .toList();

      await _api.post('/contacts/batch', data: {'contacts': contacts});
      await _db.markEventsSynced(events.map((e) => e.id).toList());
    } catch (e) {
      // Silently fail — will retry next week
    }
  }

  Future<void> _pushRuleConfigToNative() async {
    try {
      final rule = await _db.getRule();
      final user = await _db.getUser();
      final templates = await _db.getTemplates();
      final landingUrl = user == null ? '' : '$landingBaseUrl/${user.id}';
      final appendWebsiteUrlToSms = await _readAppendWebsiteUrlSetting();

      if (rule == null) return;

      final config = {
        'rules': jsonDecode(rule.configJson),
        'business_name': user?.businessName ?? '',
        'plan': user?.plan ?? 'none',
        'plan_expires_at': user?.planExpiresAt?.millisecondsSinceEpoch ?? 0,
        'landing_url': landingUrl,
        'append_website_url_to_sms': appendWebsiteUrlToSms,
        'templates': templates
            .map((t) => {
                  'id': t.serverId ?? t.id,
                  'body': t.body,
                  'image_path': t.imagePath,
                })
            .toList(),
      };

      await _bridge.updateRuleConfig(jsonEncode(config));
    } catch (_) {}
  }

  Future<void> pushLocalConfigToNative() async {
    await _pushRuleConfigToNative();
  }

  Future<bool> _readAppendWebsiteUrlSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(appendWebsiteUrlToSmsPrefKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> pushRuleConfig(String configJson) async {
    try {
      await _api.put('/rules', data: {'config': jsonDecode(configJson)});
    } catch (_) {}
  }
}
