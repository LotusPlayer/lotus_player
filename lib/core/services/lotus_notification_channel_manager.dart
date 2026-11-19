// ==============================================================================
// LOTUS PLAYER - RESILIENT NOTIFICATION CHANNEL MANAGER (MEDIA3 CLEAN MASTER)
// File: lib/core/services/lotus_notification_channel_manager.dart
// Features: Permanent Clean Channel IDs, Pre-registered Silent Playback Channel,
//           One-Time Legacy Channel Cleanup (Purges v7 through v11), Zero-Jank Background
// Compatible: Flutter 3.27+ / Flutter 3.50+ / Android 14, 15, 16 / Media3
// ==============================================================================

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LotusNotificationChannelManager {
  LotusNotificationChannelManager._();

  static final LotusNotificationChannelManager instance =
  LotusNotificationChannelManager._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  /// Primary playback channel: Permanent Media3 ID matching LotusMediaPlaybackService.kt & MainActivity.kt
  static const String channelPlayingNotifId =
      'com.souljalazian.lotus_player.media_controls_v2';

  /// Auxiliary channels owned by flutter_local_notifications
  static const String channelPlaybackServiceId =
      'com.souljalazian.lotus_player.service';

  static const String channelNewMusicId =
      'com.souljalazian.lotus_player.new_music';

  static const String _kLegacyCleanupKey = 'lotus_legacy_channels_cleaned_media3_v2';

  /// Legacy channel IDs to clean up on upgrade (purges old v7 through v11 channels)
  static const List<String> _legacyChannelIds = <String>[
    'com.souljalazian.lotus_player.playback',
    'com.souljalazian.lotus_player.playback_v11',
    'com.souljalazian.lotus_player.service_v11',
    'com.souljalazian.lotus_player.new_music_v11',
    'com.souljalazian.lotus_player.playback_v10',
    'com.souljalazian.lotus_player.service_v10',
    'com.souljalazian.lotus_player.new_music_v10',
    'com.souljalazian.lotus_player.playback_v9',
    'com.souljalazian.lotus_player.service_v9',
    'com.souljalazian.lotus_player.new_music_v9',
    'com.souljalazian.lotus_player.playback_v8',
    'com.souljalazian.lotus_player.service_v8',
    'com.souljalazian.lotus_player.new_music_v8',
    'com.souljalazian.lotus_player.playback_v7',
    'com.souljalazian.lotus_player.service_v7',
  ];

  bool _isPluginInitialized = false;
  Future<void>? _initializationFuture;

  Future<void> initializeNotificationChannels({
    bool requestPermissionOnBoot = false,
  }) {
    if (!Platform.isAndroid) {
      return Future<void>.value();
    }

    return _initializationFuture ??= _initialize(
      requestPermissionOnBoot: requestPermissionOnBoot,
    ).catchError((Object error, StackTrace stackTrace) {
      debugPrint('Lotus notification initialization error: $error');
      _initializationFuture = null;
    });
  }

  Future<void> _initialize({
    required bool requestPermissionOnBoot,
  }) async {
    if (requestPermissionOnBoot) {
      unawaited(requestNotificationPermissionIfNeeded());
    }

    if (!_isPluginInitialized) {
      bool initialized = false;

      try {
        const InitializationSettings settings = InitializationSettings(
          android: AndroidInitializationSettings('drawable/ic_stat_lotus'),
        );
        await _notificationsPlugin.initialize(settings: settings);
        initialized = true;
      } catch (_) {}

      if (!initialized) {
        try {
          const InitializationSettings fallbackSettings =
          InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          );
          await _notificationsPlugin.initialize(settings: fallbackSettings);
          initialized = true;
        } catch (e) {
          debugPrint('Lotus notification plugin fallback error: $e');
        }
      }

      _isPluginInitialized = initialized;
    }

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation == null) return;

    const AndroidNotificationChannel serviceChannel =
    AndroidNotificationChannel(
      channelPlaybackServiceId,
      'Audio Background Service',
      description: 'Notifications for Lotus Player background services.',
      importance: Importance.low,
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    const AndroidNotificationChannel newMusicChannel =
    AndroidNotificationChannel(
      channelNewMusicId,
      'New Music Discovered',
      description: 'Alerts when new audio files are discovered.',
      importance: Importance.defaultImportance,
      showBadge: true,
      enableVibration: true,
      playSound: true,
    );

    try {
      await androidImplementation.createNotificationChannel(serviceChannel);
      await androidImplementation.createNotificationChannel(newMusicChannel);
    } catch (e) {
      debugPrint('Lotus createNotificationChannel notice: $e');
    }

    unawaited(_deleteLegacyChannelsOnce(androidImplementation));
  }

  Future<void> _deleteLegacyChannelsOnce(
      AndroidFlutterLocalNotificationsPlugin android,
      ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool alreadyCleaned = prefs.getBool(_kLegacyCleanupKey) ?? false;
      if (alreadyCleaned) return;

      for (final String legacyId in _legacyChannelIds) {
        try {
          // In flutter_local_notifications modern API, channelId is a named parameter:
          // deleteNotificationChannel({required String channelId})
          await android.deleteNotificationChannel(channelId: legacyId);
        } catch (_) {}
      }

      await prefs.setBool(_kLegacyCleanupKey, true);
    } catch (e) {
      debugPrint('Lotus legacy channel cleanup notice: $e');
    }
  }

  Future<bool> requestNotificationPermissionIfNeeded() async {
    if (!Platform.isAndroid) return true;

    try {
      PermissionStatus status = await Permission.notification.status;
      if (status.isGranted) return true;

      status = await Permission.notification.request();
      return status.isGranted;
    } catch (error) {
      debugPrint('Lotus notification permission request error: $error');
      return false;
    }
  }

  Future<bool> areCorePlaybackPermissionsGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      final PermissionStatus status = await Permission.notification.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<void> showNewMusicNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid || !_isPluginInitialized) return;

    try {
      const AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
        channelNewMusicId,
        'New Music Discovered',
        channelDescription: 'Alerts when new audio files are discovered.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: 'drawable/ic_stat_lotus',
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
      );

      // In modern flutter_local_notifications, show requires named parameters:
      // show({required int id, String? title, String? body, NotificationDetails? notificationDetails, String? payload})
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('Lotus showNewMusicNotification error: $e');
    }
  }
}
