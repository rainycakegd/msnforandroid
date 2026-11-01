// lib/services/notification_service.dart
//
// Wiring (3 small edits, none of them in this file):
//
//   main.dart, in main(), right after Firebase.initializeApp():
//     await NotificationService.instance.init();
//
//   main.dart, in MaterialApp(...):
//     navigatorKey: NotificationService.navigatorKey,
//
//   chat_screen.dart:
//     initState: NotificationService.instance.activePeerId = widget.peerId;
//     dispose:   NotificationService.instance.activePeerId = null;
//
// Server side: send an FCM "notification" message to every token stored in
// users/{recipientUid}/devices/*, with data: { peerId: <senderUid>,
// peerName: <senderName> } and android.notification.channel_id = "messages".
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart' show AppRoutes, ChatRouteArgs;

/// Runs in a background isolate when a data message arrives while the app is
/// not in the foreground. Notification messages are shown by the system.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Pass this to MaterialApp.navigatorKey.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static const String channelId = 'messages';
  static const String channelName = 'Messages';
  static const String channelDescription = 'New chat messages and nudges';

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Set by the chat screen so messages from the open chat are not shown.
  String? activePeerId;

  bool _initialized = false;
  String? _registeredUid;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _openFromPayload(response.payload);
      },
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.high,
          ),
        );

    // Android 13+ runtime permission (no-op on older versions).
    try {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openChat(message.data);
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _handleLaunch());
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _initialized = false;
  }

  // ---------------------------------------------------------------------------
  // Token registration
  // ---------------------------------------------------------------------------

  Future<void> _onAuthChanged(User? user) async {
    if (user == null) {
      await _tokenSub?.cancel();
      _tokenSub = null;
      if (_registeredUid != null) {
        _registeredUid = null;
        // Invalidate this device's token so it stops receiving the previous
        // account's notifications. A new token is issued on next sign-in.
        try {
          await _fcm.deleteToken();
        } catch (_) {}
      }
      return;
    }

    _registeredUid = user.uid;
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(user.uid, token);
    } catch (e) {
      debugPrint('Could not fetch FCM token: $e');
    }

    await _tokenSub?.cancel();
    _tokenSub = _fcm.onTokenRefresh.listen((token) {
      final uid = _registeredUid;
      if (uid != null) _saveToken(uid, token);
    });
  }

  Future<void> _saveToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .set(<String, dynamic>{
        'token': token,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Could not save FCM token: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Incoming messages
  // ---------------------------------------------------------------------------

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final peerId = message.data['peerId'] as String?;
    if (peerId != null && peerId == activePeerId) return;

    final notification = message.notification;
    final title = notification?.title ?? message.data['peerName'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null && body == null) return;

    await _local.show(
      message.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // ---------------------------------------------------------------------------
  // Opening a chat from a notification
  // ---------------------------------------------------------------------------

  Future<void> _handleLaunch() async {
    // App started by tapping an FCM notification.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _openChat(initial.data);
      return;
    }
    // App started by tapping a notification shown by this plugin.
    final details = await _local.getNotificationAppLaunchDetails();
    if (details != null && details.didNotificationLaunchApp) {
      _openFromPayload(details.notificationResponse?.payload);
    }
  }

  void _openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _openChat(decoded.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (_) {}
  }

  void _openChat(Map<String, dynamic> data) {
    final peerId = data['peerId'] as String?;
    if (peerId == null || peerId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    if (peerId == activePeerId) return;

    final peerName = (data['peerName'] as String?) ?? 'Chat';
    navigatorKey.currentState?.pushNamed(
      AppRoutes.chat,
      arguments: ChatRouteArgs(peerId: peerId, peerName: peerName),
    );
  }
}