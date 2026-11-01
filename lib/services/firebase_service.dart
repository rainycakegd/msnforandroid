// lib/services/firebase_service.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/constants.dart';

/// A user profile stored in `users/{uid}`.
class AppUser {
  final String uid;
  final String email;
  final String displayName;
  final String statusMessage;
  final String nowPlaying;
  final String? avatarUrl;
  final UserStatus status;
  final DateTime? lastSeen;

  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.statusMessage = '',
    this.nowPlaying = '',
    this.avatarUrl,
    this.status = UserStatus.offline,
    this.lastSeen,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    final lastSeen = data[UserFields.lastSeen];
    return AppUser(
      uid: uid,
      email: (data[UserFields.email] as String?) ?? '',
      displayName: (data[UserFields.displayName] as String?) ?? 'Unknown',
      statusMessage: (data[UserFields.statusMessage] as String?) ?? '',
      nowPlaying: (data[UserFields.nowPlaying] as String?) ?? '',
      avatarUrl: data[UserFields.avatarUrl] as String?,
      status: UserStatusX.fromString(data[UserFields.status] as String?),
      lastSeen: lastSeen is Timestamp ? lastSeen.toDate() : null,
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }
}

/// A chat message stored in `chats/{chatId}/messages/{messageId}`.
class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final DateTime createdAt;
  final List<String> readBy;

  /// True while the message has not yet been confirmed by the server.
  final bool pending;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    required this.readBy,
    this.pending = false,
  });

  bool isReadBy(String uid) => readBy.contains(uid);

  factory ChatMessage.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final created = data[MessageFields.createdAt];
    final rawRead = data[MessageFields.readBy];
    return ChatMessage(
      id: doc.id,
      senderId: (data[MessageFields.senderId] as String?) ?? '',
      text: (data[MessageFields.text] as String?) ?? '',
      type: MessageTypeX.fromString(data[MessageFields.type] as String?),
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      readBy: rawRead is List
          ? rawRead.map((e) => e.toString()).toList()
          : <String>[],
      pending: doc.metadata.hasPendingWrites,
    );
  }
}

/// Wraps Firebase Auth, Firestore and Storage for the whole app.
class FirebaseService {
  FirebaseService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  final Map<String, DateTime> _lastNudgeSent = <String, DateTime>{};

  // ---------------------------------------------------------------------------
  // Collection helpers
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(FirestoreCollections.users);

  CollectionReference<Map<String, dynamic>> get _chats =>
      _db.collection(FirestoreCollections.chats);

  CollectionReference<Map<String, dynamic>> _messages(String chatId) =>
      _chats.doc(chatId).collection(FirestoreCollections.messages);

  /// Deterministic chat id for two users.
  static String chatIdFor(String uidA, String uidB) {
    final sorted = <String>[uidA, uidB]..sort();
    return sorted.join('_');
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  User? get currentUser => _auth.currentUser;

  String get currentUid {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user.');
    }
    return user.uid;
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User> signIn({
    required String email,
    required String password,
    UserStatus initialStatus = UserStatus.online,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await _ensureUserDoc(user);
    await _users.doc(user.uid).set(<String, dynamic>{
      UserFields.status: initialStatus.value,
      UserFields.lastSeen: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return user;
  }

  Future<User> register({
    required String email,
    required String password,
    required String displayName,
    String statusMessage = '',
    File? avatar,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    final name = displayName.trim();
    await user.updateDisplayName(name);

    String? avatarUrl;
    if (avatar != null) {
      try {
        avatarUrl = await uploadAvatar(user.uid, avatar);
      } catch (_) {
        // The account is still created if the avatar upload fails.
        avatarUrl = null;
      }
    }

    await _users.doc(user.uid).set(<String, dynamic>{
      UserFields.uid: user.uid,
      UserFields.email: email.trim(),
      UserFields.emailLower: email.trim().toLowerCase(),
      UserFields.displayName: name,
      UserFields.displayNameLower: name.toLowerCase(),
      UserFields.statusMessage: statusMessage.trim(),
      UserFields.nowPlaying: '',
      UserFields.avatarUrl: avatarUrl,
      UserFields.status: UserStatus.online.value,
      UserFields.lastSeen: FieldValue.serverTimestamp(),
      UserFields.createdAt: FieldValue.serverTimestamp(),
    });
    return user;
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _users.doc(user.uid).set(<String, dynamic>{
          UserFields.status: UserStatus.offline.value,
          UserFields.lastSeen: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
      } catch (_) {
        // Sign out even if the presence update could not be delivered.
      }
    }
    await _auth.signOut();
  }

  Future<void> _ensureUserDoc(User user) async {
    final doc = await _users.doc(user.uid).get();
    if (doc.exists) return;
    final name = (user.displayName != null && user.displayName!.isNotEmpty)
        ? user.displayName!
        : (user.email ?? 'User').split('@').first;
    await _users.doc(user.uid).set(<String, dynamic>{
      UserFields.uid: user.uid,
      UserFields.email: user.email ?? '',
      UserFields.emailLower: (user.email ?? '').toLowerCase(),
      UserFields.displayName: name,
      UserFields.displayNameLower: name.toLowerCase(),
      UserFields.statusMessage: '',
      UserFields.nowPlaying: '',
      UserFields.avatarUrl: user.photoURL,
      UserFields.status: UserStatus.online.value,
      UserFields.lastSeen: FieldValue.serverTimestamp(),
      UserFields.createdAt: FieldValue.serverTimestamp(),
    });
  }

  /// Converts auth errors to friendly, MSN-style messages.
  static String authErrorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That e-mail address does not look right.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return 'Incorrect e-mail address or password.';
        case 'email-already-in-use':
          return 'An account with this e-mail already exists.';
        case 'weak-password':
          return 'Please choose a stronger password (6+ characters).';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'No connection. Check your internet and try again.';
        case 'operation-not-allowed':
          return 'E-mail sign-in is not enabled for this app.';
        default:
          return error.message ?? 'Sign-in failed. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  // ---------------------------------------------------------------------------
  // Profile & presence
  // ---------------------------------------------------------------------------

  Future<String> uploadAvatar(String uid, File file) async {
    final ref = _storage
        .ref()
        .child(AppConstants.storageAvatars)
        .child('$uid.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Stream<AppUser?> userStream(String uid) {
    return _users.doc(uid).snapshots().map(
          (doc) => doc.exists ? AppUser.fromDoc(doc) : null,
        );
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  Future<void> setStatus(UserStatus status) {
    return _users.doc(currentUid).set(<String, dynamic>{
      UserFields.status: status.value,
      UserFields.lastSeen: FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProfile({
    String? displayName,
    String? statusMessage,
    String? nowPlaying,
    File? avatar,
  }) async {
    final uid = currentUid;
    final updates = <String, dynamic>{};

    if (displayName != null && displayName.trim().isNotEmpty) {
      final name = displayName.trim();
      updates[UserFields.displayName] = name;
      updates[UserFields.displayNameLower] = name.toLowerCase();
      await _auth.currentUser?.updateDisplayName(name);
    }
    if (statusMessage != null) {
      updates[UserFields.statusMessage] = statusMessage.trim();
    }
    if (nowPlaying != null) {
      updates[UserFields.nowPlaying] = nowPlaying.trim();
    }
    if (avatar != null) {
      updates[UserFields.avatarUrl] = await uploadAvatar(uid, avatar);
    }

    if (updates.isNotEmpty) {
      await _users.doc(uid).set(updates, SetOptions(merge: true));
    }
  }

  // ---------------------------------------------------------------------------
  // Messaging
  // ---------------------------------------------------------------------------

  /// Newest-first stream of messages for the chat with [peerId].
  Stream<List<ChatMessage>> messagesStream(String peerId) {
    final chatId = chatIdFor(currentUid, peerId);
    return _messages(chatId)
        .orderBy(MessageFields.createdAt, descending: true)
        .limit(AppConstants.messagePageSize)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snap) => snap.docs.map(ChatMessage.fromDoc).toList(growable: false),
        );
  }

  Future<void> sendMessage({
    required String peerId,
    required String text,
    MessageType type = MessageType.text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final me = currentUid;
    final chatId = chatIdFor(me, peerId);
    final msgRef = _messages(chatId).doc();
    final chatRef = _chats.doc(chatId);

    final batch = _db.batch();
    batch.set(msgRef, <String, dynamic>{
      MessageFields.id: msgRef.id,
      MessageFields.senderId: me,
      MessageFields.text: trimmed,
      MessageFields.type: type.value,
      MessageFields.createdAt: FieldValue.serverTimestamp(),
      MessageFields.readBy: <String>[me],
    });
    batch.set(
      chatRef,
      <String, dynamic>{
        ChatFields.participants: <String>[me, peerId],
        ChatFields.lastMessage: trimmed,
        ChatFields.lastMessageAt: FieldValue.serverTimestamp(),
        ChatFields.typing: <String, dynamic>{me: FieldValue.delete()},
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Marks all unread messages from [peerId] as read by the current user.
  Future<void> markMessagesRead(String peerId) async {
    final me = currentUid;
    final chatId = chatIdFor(me, peerId);

    final snap = await _messages(chatId)
        .orderBy(MessageFields.createdAt, descending: true)
        .limit(AppConstants.messagePageSize)
        .get();

    final batch = _db.batch();
    var count = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final sender = data[MessageFields.senderId];
      final readBy = data[MessageFields.readBy];
      final alreadyRead = readBy is List && readBy.contains(me);
      if (sender == peerId && !alreadyRead) {
        batch.update(doc.reference, <String, dynamic>{
          MessageFields.readBy: FieldValue.arrayUnion(<String>[me]),
        });
        count++;
      }
    }
    if (count > 0) {
      await batch.commit();
    }
  }

  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  /// Call with `true` while the user is typing (re-send every ~2s) and
  /// with `false` when they stop or send.
  Future<void> setTyping(String peerId, bool isTyping) async {
    final me = currentUid;
    final chatId = chatIdFor(me, peerId);
    await _chats.doc(chatId).set(
      <String, dynamic>{
        ChatFields.participants: <String>[me, peerId],
        ChatFields.typing: <String, dynamic>{
          me: isTyping ? Timestamp.now() : FieldValue.delete(),
        },
      },
      SetOptions(merge: true),
    );
  }

  /// Emits `true` while the peer is typing, `false` otherwise.
  Stream<bool> peerTypingStream(String peerId) {
    final chatId = chatIdFor(currentUid, peerId);

    late final StreamController<bool> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
    Timer? expiry;

    controller = StreamController<bool>(
      onListen: () {
        sub = _chats.doc(chatId).snapshots().listen(
          (snap) {
            expiry?.cancel();
            final data = snap.data();
            final typing = data == null ? null : data[ChatFields.typing];
            final stamp = typing is Map ? typing[peerId] : null;

            if (stamp is Timestamp) {
              final age = DateTime.now().difference(stamp.toDate());
              final remaining = AppConstants.typingTimeout - age;
              if (remaining > Duration.zero) {
                controller.add(true);
                expiry = Timer(remaining, () {
                  if (!controller.isClosed) controller.add(false);
                });
                return;
              }
            }
            controller.add(false);
          },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        expiry?.cancel();
        await sub?.cancel();
      },
    );

    return controller.stream.distinct();
  }

  // ---------------------------------------------------------------------------
  // Nudge
  // ---------------------------------------------------------------------------

  /// Sends a nudge. Returns `false` if the cooldown has not elapsed yet.
  Future<bool> sendNudge(String peerId) async {
    final now = DateTime.now();
    final last = _lastNudgeSent[peerId];
    if (last != null && now.difference(last) < AppConstants.nudgeCooldown) {
      return false;
    }
    _lastNudgeSent[peerId] = now;

    final me = currentUid;
    final chatId = chatIdFor(me, peerId);
    final msgRef = _messages(chatId).doc();
    final chatRef = _chats.doc(chatId);

    final batch = _db.batch();
    batch.set(msgRef, <String, dynamic>{
      MessageFields.id: msgRef.id,
      MessageFields.senderId: me,
      MessageFields.text: 'sent a nudge',
      MessageFields.type: MessageType.nudge.value,
      MessageFields.createdAt: FieldValue.serverTimestamp(),
      MessageFields.readBy: <String>[me],
    });
    batch.set(
      chatRef,
      <String, dynamic>{
        ChatFields.participants: <String>[me, peerId],
        ChatFields.lastNudgeAt: FieldValue.serverTimestamp(),
        ChatFields.lastNudgeBy: me,
        ChatFields.lastMessage: 'Nudge!',
        ChatFields.lastMessageAt: FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    return true;
  }

  /// Emits a timestamp each time [peerId] nudges the current user.
  /// Stale nudges (older than 10 seconds) are ignored.
  Stream<DateTime> incomingNudgeStream(String peerId) {
    final chatId = chatIdFor(currentUid, peerId);
    return _chats
        .doc(chatId)
        .snapshots()
        .map<DateTime?>((snap) {
          final data = snap.data();
          if (data == null) return null;
          if (data[ChatFields.lastNudgeBy] != peerId) return null;
          final at = data[ChatFields.lastNudgeAt];
          if (at is! Timestamp) return null;
          final time = at.toDate();
          if (DateTime.now().difference(time) > const Duration(seconds: 10)) {
            return null;
          }
          return time;
        })
        .where((time) => time != null)
        .cast<DateTime>()
        .distinct();
  }
}

// -----------------------------------------------------------------------------
// Riverpod providers
// -----------------------------------------------------------------------------

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

final messagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, peerId) {
  return ref.watch(firebaseServiceProvider).messagesStream(peerId);
});

final peerTypingProvider =
    StreamProvider.autoDispose.family<bool, String>((ref, peerId) {
  return ref.watch(firebaseServiceProvider).peerTypingStream(peerId);
});

final incomingNudgeProvider =
    StreamProvider.autoDispose.family<DateTime, String>((ref, peerId) {
  return ref.watch(firebaseServiceProvider).incomingNudgeStream(peerId);
});

final userProfileProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  return ref.watch(firebaseServiceProvider).userStream(uid);
});