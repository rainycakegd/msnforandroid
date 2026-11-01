// lib/utils/constants.dart
import 'package:flutter/material.dart';

/// App-wide constants.
class AppConstants {
  static const String appName = 'Aero Messenger';

  // Local storage keys
  static const String prefThemeId = 'pref_theme_id';
  static const String prefLastEmail = 'pref_last_email';

  // Firebase Storage paths
  static const String storageAvatars = 'avatars';

  // Asset paths
  static const String soundNudge = 'sounds/nudge.mp3';
  static const String soundMessage = 'sounds/message.mp3';
  static const String soundOnline = 'sounds/online.mp3';
  static const String emoticonsDir = 'assets/emoticons/';
  static const String iconsDir = 'assets/icons/';

  // Behaviour tuning
  static const Duration typingTimeout = Duration(seconds: 4);
  static const Duration nudgeCooldown = Duration(seconds: 10);
  static const Duration nudgeShakeDuration = Duration(milliseconds: 700);
  static const int messagePageSize = 50;
  static const int maxDisplayNameLength = 24;
  static const int maxStatusMessageLength = 80;
}

/// Firestore collection and field names.
class FirestoreCollections {
  static const String users = 'users';
  static const String contacts = 'contacts';
  static const String friendRequests = 'friend_requests';
  static const String blocked = 'blocked';
  static const String chats = 'chats';
  static const String messages = 'messages';
}

class UserFields {
  static const String uid = 'uid';
  static const String email = 'email';
  static const String emailLower = 'emailLower';
  static const String displayName = 'displayName';
  static const String displayNameLower = 'displayNameLower';
  static const String statusMessage = 'statusMessage';
  static const String nowPlaying = 'nowPlaying';
  static const String avatarUrl = 'avatarUrl';
  static const String status = 'status';
  static const String lastSeen = 'lastSeen';
  static const String createdAt = 'createdAt';
}

class MessageFields {
  static const String id = 'id';
  static const String senderId = 'senderId';
  static const String text = 'text';
  static const String type = 'type';
  static const String createdAt = 'createdAt';
  static const String readBy = 'readBy';
}

class ChatFields {
  static const String participants = 'participants';
  static const String lastMessage = 'lastMessage';
  static const String lastMessageAt = 'lastMessageAt';
  static const String typing = 'typing';
  static const String lastNudgeAt = 'lastNudgeAt';
  static const String lastNudgeBy = 'lastNudgeBy';
}

class RequestFields {
  static const String fromUid = 'fromUid';
  static const String toUid = 'toUid';
  static const String status = 'status';
  static const String createdAt = 'createdAt';
}

/// Presence status shown next to every buddy.
enum UserStatus { online, away, busy, offline }

extension UserStatusX on UserStatus {
  String get value => name;

  String get label {
    switch (this) {
      case UserStatus.online:
        return 'Online';
      case UserStatus.away:
        return 'Away';
      case UserStatus.busy:
        return 'Busy';
      case UserStatus.offline:
        return 'Offline';
    }
  }

  Color get color {
    switch (this) {
      case UserStatus.online:
        return AeroColors.online;
      case UserStatus.away:
        return AeroColors.away;
      case UserStatus.busy:
        return AeroColors.busy;
      case UserStatus.offline:
        return AeroColors.offline;
    }
  }

  Color get highlightColor {
    switch (this) {
      case UserStatus.online:
        return AeroColors.onlineLight;
      case UserStatus.away:
        return AeroColors.awayLight;
      case UserStatus.busy:
        return AeroColors.busyLight;
      case UserStatus.offline:
        return AeroColors.offlineLight;
    }
  }

  /// Sort order for the buddy list (online first).
  int get sortOrder {
    switch (this) {
      case UserStatus.online:
        return 0;
      case UserStatus.busy:
        return 1;
      case UserStatus.away:
        return 2;
      case UserStatus.offline:
        return 3;
    }
  }

  static UserStatus fromString(String? raw) {
    for (final status in UserStatus.values) {
      if (status.name == raw) return status;
    }
    return UserStatus.offline;
  }
}

enum RequestStatus { pending, accepted, declined }

extension RequestStatusX on RequestStatus {
  String get value => name;

  static RequestStatus fromString(String? raw) {
    for (final status in RequestStatus.values) {
      if (status.name == raw) return status;
    }
    return RequestStatus.pending;
  }
}

enum MessageType { text, nudge, system }

extension MessageTypeX on MessageType {
  String get value => name;

  static MessageType fromString(String? raw) {
    for (final type in MessageType.values) {
      if (type.name == raw) return type;
    }
    return MessageType.text;
  }
}

/// The three selectable color themes.
enum AeroThemeId { msnClassic, aquaGreen, sunsetOrange }

/// Default (theme independent) colors.
class AeroColors {
  // Signature MSN blue
  static const Color msnBlueDark = Color(0xFF0B5CAB);
  static const Color msnBlueLight = Color(0xFF9FD4FF);
  static const Color msnBlueMid = Color(0xFF3FA9F5);

  // Status colors
  static const Color online = Color(0xFF3DBE29);
  static const Color onlineLight = Color(0xFFB8F5A8);
  static const Color away = Color(0xFFF2B01E);
  static const Color awayLight = Color(0xFFFFE9A6);
  static const Color busy = Color(0xFFF26B1D);
  static const Color busyLight = Color(0xFFFFCDA6);
  static const Color offline = Color(0xFF9AA5B1);
  static const Color offlineLight = Color(0xFFE3E8EE);

  // Text
  static const Color textDark = Color(0xFF0A2E57);
  static const Color textMuted = Color(0xFF5B7A99);

  // Feedback
  static const Color error = Color(0xFFD64545);
  static const Color success = Color(0xFF2E8B3D);

  // Smiley yellow
  static const Color smileyYellow = Color(0xFFFFD83D);
  static const Color smileyYellowDark = Color(0xFFE8A800);
}

/// Text shortcuts that are rendered as emoticon images in chat.
class Emoticons {
  /// Maps a typed shortcut to its asset file name in assets/emoticons/.
  static const Map<String, String> shortcuts = <String, String>{
    ':)': 'smile.png',
    ':-)': 'smile.png',
    ':D': 'grin.png',
    ':-D': 'grin.png',
    ';)': 'wink.png',
    ';-)': 'wink.png',
    ':(': 'sad.png',
    ':-(': 'sad.png',
    ':P': 'tongue.png',
    ':-P': 'tongue.png',
    ':O': 'surprised.png',
    ':-O': 'surprised.png',
    ":'(": 'cry.png',
    ':@': 'angry.png',
    ':S': 'confused.png',
    ':|': 'neutral.png',
    '8-)': 'cool.png',
    '(H)': 'cool.png',
    ':\$': 'embarrassed.png',
    '(L)': 'heart.png',
    '(A)': 'angel.png',
    '(6)': 'devil.png',
  };
}