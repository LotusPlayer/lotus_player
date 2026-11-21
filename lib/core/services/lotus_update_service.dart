import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../theme/lotus_theme.dart';
import '../widgets/lotus_widgets.dart';

/// Service managing remote update detection, in-app streaming APK download,
/// and native PackageInstaller dispatch for Lotus Player.
class LotusUpdateService {
  static String currentVersion = '3.2.2';
  static int currentBuildNumber = 422;
  static bool _hasLoadedAppInfo = false;

  /// Dynamic build architecture label reflecting the exact running version
  static String get buildArchitecture => 'Rise & Bloom v$currentVersion';

  /// Queries the Android Package Manager dynamically to fetch the real installed APK version
  static Future<void> initAppVersion() async {
    if (_hasLoadedAppInfo) return;
    try {
      final dynamic result = await _updaterChannel.invokeMethod('getAppInfo');
      if (result is Map) {
        final String? v = result['version']?.toString();
        final int? b = (result['buildNumber'] as num?)?.toInt();
        if (v != null && v.isNotEmpty) {
          currentVersion = v;
        }
        if (b != null && b > 0) {
          currentBuildNumber = b;
        }
        _hasLoadedAppInfo = true;
      }
    } catch (_) {
      // Fallback to defaults
    }
  }

  static const String versionEndpoint =
      'https://lotusplayer.github.io/lotus_player/version.json';

  static const MethodChannel _updaterChannel =
      MethodChannel('com.souljalazian.lotus_player/updater');

  static bool _isChecking = false;

  /// Checks for updates. If [isManual] is true (e.g. tapped from Settings),
  /// feedback is shown even if the app is already on the latest edition.
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool isManual = false,
  }) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      await initAppVersion();
      final Uri uri = Uri.parse(
        '$versionEndpoint?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (isManual && context.mounted) {
          LotusSnackBar.show(
            context,
            message: 'Unable to check for updates (server status ${response.statusCode}).',
            icon: Icons.cloud_off_rounded,
          );
        }
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final String remoteVersion = (data['version'] ?? currentVersion).toString();
      final int remoteBuildNumber = (data['build_number'] as num?)?.toInt() ?? 0;
      final String downloadUrl = (data['download_url'] ?? '').toString();
      final String changelog = (data['changelog'] ?? 'Stability and UI enhancements.').toString();

      final bool hasUpdate = remoteBuildNumber > currentBuildNumber ||
          _isVersionHigher(remoteVersion, currentVersion);

      if (!context.mounted) return;

      if (hasUpdate && downloadUrl.isNotEmpty) {
        _showUpdateDialog(
          context,
          remoteVersion: remoteVersion,
          remoteBuildNumber: remoteBuildNumber,
          downloadUrl: downloadUrl,
          changelog: changelog,
        );
      } else if (isManual) {
        LotusSnackBar.show(
          context,
          message: 'Lotus Player is up to date! (v$currentVersion)',
          icon: Icons.check_circle_rounded,
        );
      }
    } catch (e) {
      if (isManual && context.mounted) {
        LotusSnackBar.show(
          context,
          message: 'Could not connect to update server. Check your connection.',
          icon: Icons.wifi_off_rounded,
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  static bool _isVersionHigher(String remote, String current) {
    try {
      final List<int> rParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final List<int> cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < rParts.length && i < cParts.length; i++) {
        if (rParts[i] > cParts[i]) return true;
        if (rParts[i] < cParts[i]) return false;
      }
      return rParts.length > cParts.length;
    } catch (_) {
      return false;
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String remoteVersion,
    required int remoteBuildNumber,
    required String downloadUrl,
    required String changelog,
  }) {
    final theme = LotusThemeController.instance;
    final isWhitaniana = theme.isWhitanianaActive;
    final primaryAccent = theme.primaryAccent;
    final cardBg = isWhitaniana ? LotusColors.whitanianaPureWhiteCard : theme.containerHighColor;
    final textColor = isWhitaniana ? LotusColors.whitanianaTextPrimary : Colors.white;
    final subtitleColor = isWhitaniana ? LotusColors.whitanianaTextSecondary : Colors.white70;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cardBg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: primaryAccent.withValues(alpha: 0.4), width: 1.5),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.system_update_rounded, color: primaryAccent, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Update Available',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      'Version $remoteVersion (Build $remoteBuildNumber)',
                      style: TextStyle(
                        color: primaryAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new edition of Lotus Player is ready to install:',
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryAccent.withValues(alpha: 0.2)),
                ),
                child: Text(
                  changelog,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'LATER',
                style: TextStyle(
                  color: subtitleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: isWhitaniana ? Colors.white : Colors.black,
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _startDownloadAndInstall(context, downloadUrl, remoteVersion);
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'UPDATE NOW',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        );
      },
    );
  }

  static void _startDownloadAndInstall(
    BuildContext context,
    String downloadUrl,
    String version,
  ) {
    final theme = LotusThemeController.instance;
    final isWhitaniana = theme.isWhitanianaActive;
    final primaryAccent = theme.primaryAccent;
    final cardBg = isWhitaniana ? LotusColors.whitanianaPureWhiteCard : theme.containerHighColor;
    final textColor = isWhitaniana ? LotusColors.whitanianaTextPrimary : Colors.white;

    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
    final ValueNotifier<String> statusNotifier = ValueNotifier<String>('Starting download...');
    bool isCancelled = false;
    http.Client? client;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: cardBg,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: primaryAccent.withValues(alpha: 0.4), width: 1.5),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            title: Row(
              children: [
                Icon(Icons.downloading_rounded, color: primaryAccent, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Downloading Update',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: AnimatedBuilder(
              animation: progressNotifier,
              builder: (ctx, _) {
                final double progress = progressNotifier.value;
                final int percent = (progress * 100).clamp(0, 100).toInt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 8,
                        backgroundColor: primaryAccent.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<String>(
                            valueListenable: statusNotifier,
                            builder: (ctx, status, _) => Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isWhitaniana
                                    ? LotusColors.whitanianaTextSecondary
                                    : Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '$percent%',
                          style: TextStyle(
                            color: primaryAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  isCancelled = true;
                  client?.close();
                  Navigator.of(dialogCtx).pop();
                },
                child: Text(
                  'CANCEL',
                  style: TextStyle(
                    color: isWhitaniana
                        ? LotusColors.whitanianaTextSecondary
                        : Colors.white60,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    // Download execution
    () async {
      client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(downloadUrl));
        final response = await client!.send(request);

        if (response.statusCode != 200) {
          throw HttpException('Server returned HTTP ${response.statusCode}');
        }

        final int totalBytes = response.contentLength ?? 0;
        int receivedBytes = 0;

        final Directory tempDir = await getTemporaryDirectory();
        final File apkFile = File('${tempDir.path}/LotusPlayer_v$version.apk');
        if (await apkFile.exists()) {
          await apkFile.delete();
        }

        final IOSink sink = apkFile.openWrite();

        await for (final List<int> chunk in response.stream) {
          if (isCancelled) {
            await sink.close();
            if (await apkFile.exists()) await apkFile.delete();
            return;
          }
          sink.add(chunk);
          receivedBytes += chunk.length;

          if (totalBytes > 0) {
            progressNotifier.value = receivedBytes / totalBytes;
            final double mbReceived = receivedBytes / (1024 * 1024);
            final double mbTotal = totalBytes / (1024 * 1024);
            statusNotifier.value =
                '${mbReceived.toStringAsFixed(1)} MB / ${mbTotal.toStringAsFixed(1)} MB';
          } else {
            final double mbReceived = receivedBytes / (1024 * 1024);
            statusNotifier.value = '${mbReceived.toStringAsFixed(1)} MB downloaded';
          }
        }

        await sink.flush();
        await sink.close();

        if (isCancelled) return;

        // Dismiss progress dialog
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        // Invoke native installation
        await _updaterChannel.invokeMethod('installApk', {'filePath': apkFile.path});
      } catch (e) {
        if (!isCancelled) {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            LotusSnackBar.show(
              context,
              message: 'Download failed: $e',
              icon: Icons.error_outline_rounded,
            );
          }
        }
      } finally {
        client?.close();
      }
    }();
  }
}
