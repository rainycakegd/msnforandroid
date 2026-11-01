// lib/screens/buddy_list/buddy_list_screen.dart
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show AppRoutes, ChatRouteArgs, authStateChangesProvider;
import '../../services/firebase_service.dart';
import '../../theme/aero_theme.dart';
import '../../utils/constants.dart';

// -----------------------------------------------------------------------------
// Contacts data layer (buddies, friend requests, blocking)
// -----------------------------------------------------------------------------

class _ContactFields {
  static const String ownerUid = 'ownerUid';
  static const String buddyUid = 'buddyUid';
  static const String blockerUid = 'blockerUid';
  static const String blockedUid = 'blockedUid';
  static const String createdAt = 'createdAt';
}

class FriendRequest {
  final String id;
  final String fromUid;
  final String toUid;
  final RequestStatus status;
  final DateTime? createdAt;

  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.status,
    this.createdAt,
  });

  factory FriendRequest.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final created = data[RequestFields.createdAt];
    return FriendRequest(
      id: doc.id,
      fromUid: (data[RequestFields.fromUid] as String?) ?? '',
      toUid: (data[RequestFields.toUid] as String?) ?? '',
      status: RequestStatusX.fromString(data[RequestFields.status] as String?),
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

class ContactsService {
  ContactsService(this._db, this._firebase);

  final FirebaseFirestore _db;
  final FirebaseService _firebase;

  String? get _me => _firebase.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _contacts =>
      _db.collection(FirestoreCollections.contacts);
  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection(FirestoreCollections.friendRequests);
  CollectionReference<Map<String, dynamic>> get _blocked =>
      _db.collection(FirestoreCollections.blocked);
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection(FirestoreCollections.users);

  Stream<List<String>> buddyIdsStream() {
    final me = _me;
    if (me == null) return Stream<List<String>>.value(const <String>[]);
    return _contacts
        .where(_ContactFields.ownerUid, isEqualTo: me)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => (d.data()[_ContactFields.buddyUid] as String?) ?? '')
            .where((id) => id.isNotEmpty)
            .toList());
  }

  Stream<List<String>> blockedIdsStream() {
    final me = _me;
    if (me == null) return Stream<List<String>>.value(const <String>[]);
    return _blocked
        .where(_ContactFields.blockerUid, isEqualTo: me)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => (d.data()[_ContactFields.blockedUid] as String?) ?? '')
            .where((id) => id.isNotEmpty)
            .toList());
  }

  Stream<List<FriendRequest>> incomingRequestsStream() {
    final me = _me;
    if (me == null) return Stream<List<FriendRequest>>.value(const []);
    return _requests
        .where(RequestFields.toUid, isEqualTo: me)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(FriendRequest.fromDoc)
          .where((r) => r.status == RequestStatus.pending)
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime.now())
          .compareTo(a.createdAt ?? DateTime.now()));
      return list;
    });
  }

  Stream<List<FriendRequest>> outgoingRequestsStream() {
    final me = _me;
    if (me == null) return Stream<List<FriendRequest>>.value(const []);
    return _requests
        .where(RequestFields.fromUid, isEqualTo: me)
        .snapshots()
        .map((snap) => snap.docs
            .map(FriendRequest.fromDoc)
            .where((r) => r.status == RequestStatus.pending)
            .toList());
  }

  /// Searches by exact e-mail (when the query contains '@') or by display
  /// name prefix.
  Future<List<AppUser>> searchUsers(String raw) async {
    final me = _me;
    final q = raw.trim().toLowerCase();
    if (q.length < 2) return <AppUser>[];

    final found = <String, AppUser>{};

    if (q.contains('@')) {
      final snap = await _users
          .where(UserFields.emailLower, isEqualTo: q)
          .limit(5)
          .get();
      for (final doc in snap.docs) {
        found[doc.id] = AppUser.fromDoc(doc);
      }
    } else {
      final snap = await _users
          .where(UserFields.displayNameLower, isGreaterThanOrEqualTo: q)
          .where(UserFields.displayNameLower, isLessThan: '$q\uf8ff')
          .limit(15)
          .get();
      for (final doc in snap.docs) {
        found[doc.id] = AppUser.fromDoc(doc);
      }
    }

    found.remove(me);
    return found.values.toList();
  }

  Future<void> sendRequest(String toUid) async {
    final me = _firebase.currentUid;
    await _requests.doc('${me}_$toUid').set(<String, dynamic>{
      RequestFields.fromUid: me,
      RequestFields.toUid: toUid,
      RequestFields.status: RequestStatus.pending.value,
      RequestFields.createdAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptRequest(FriendRequest request) async {
    final batch = _db.batch();
    batch.update(_requests.doc(request.id), <String, dynamic>{
      RequestFields.status: RequestStatus.accepted.value,
    });
    batch.set(_contacts.doc('${request.toUid}_${request.fromUid}'),
        <String, dynamic>{
      _ContactFields.ownerUid: request.toUid,
      _ContactFields.buddyUid: request.fromUid,
      _ContactFields.createdAt: FieldValue.serverTimestamp(),
    });
    batch.set(_contacts.doc('${request.fromUid}_${request.toUid}'),
        <String, dynamic>{
      _ContactFields.ownerUid: request.fromUid,
      _ContactFields.buddyUid: request.toUid,
      _ContactFields.createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> declineRequest(FriendRequest request) {
    return _requests.doc(request.id).update(<String, dynamic>{
      RequestFields.status: RequestStatus.declined.value,
    });
  }

  Future<void> removeContact(String buddyUid) async {
    final me = _firebase.currentUid;
    final batch = _db.batch();
    batch.delete(_contacts.doc('${me}_$buddyUid'));
    batch.delete(_contacts.doc('${buddyUid}_$me'));
    batch.delete(_requests.doc('${me}_$buddyUid'));
    batch.delete(_requests.doc('${buddyUid}_$me'));
    await batch.commit();
  }

  Future<void> blockUser(String uid) {
    final me = _firebase.currentUid;
    return _blocked.doc('${me}_$uid').set(<String, dynamic>{
      _ContactFields.blockerUid: me,
      _ContactFields.blockedUid: uid,
      _ContactFields.createdAt: FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String uid) {
    final me = _firebase.currentUid;
    return _blocked.doc('${me}_$uid').delete();
  }
}

final contactsServiceProvider = Provider<ContactsService>((ref) {
  // Rebuild when the signed-in user changes.
  ref.watch(authStateChangesProvider);
  return ContactsService(
    FirebaseFirestore.instance,
    ref.watch(firebaseServiceProvider),
  );
});

final buddyIdsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  return ref.watch(contactsServiceProvider).buddyIdsStream();
});

final blockedIdsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  return ref.watch(contactsServiceProvider).blockedIdsStream();
});

final incomingRequestsProvider =
    StreamProvider.autoDispose<List<FriendRequest>>((ref) {
  return ref.watch(contactsServiceProvider).incomingRequestsStream();
});

final outgoingRequestsProvider =
    StreamProvider.autoDispose<List<FriendRequest>>((ref) {
  return ref.watch(contactsServiceProvider).outgoingRequestsStream();
});

/// Live profiles of all contacts.
final buddyUsersProvider = Provider.autoDispose<List<AppUser>>((ref) {
  final ids = ref.watch(buddyIdsProvider).valueOrNull ?? const <String>[];
  final users = <AppUser>[];
  for (final id in ids) {
    final user = ref.watch(userProfileProvider(id)).valueOrNull;
    if (user != null) users.add(user);
  }
  return users;
});

/// Live profiles of all blocked users.
final blockedUsersProvider = Provider.autoDispose<List<AppUser>>((ref) {
  final ids = ref.watch(blockedIdsProvider).valueOrNull ?? const <String>[];
  final users = <AppUser>[];
  for (final id in ids) {
    final user = ref.watch(userProfileProvider(id)).valueOrNull;
    if (user != null) users.add(user);
  }
  return users;
});

// -----------------------------------------------------------------------------
// Buddy list screen
// -----------------------------------------------------------------------------

class BuddyListScreen extends ConsumerStatefulWidget {
  const BuddyListScreen({super.key});

  @override
  ConsumerState<BuddyListScreen> createState() => _BuddyListScreenState();
}

class _BuddyListScreenState extends ConsumerState<BuddyListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<UserStatus> _collapsed = <UserStatus>{};
  String _query = '';
  bool _blockedExpanded = false;

  static const List<UserStatus> _groupOrder = <UserStatus>[
    UserStatus.online,
    UserStatus.busy,
    UserStatus.away,
    UserStatus.offline,
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(AppUser user) {
    Navigator.of(context).pushNamed(
      AppRoutes.chat,
      arguments: ChatRouteArgs(peerId: user.uid, peerName: user.displayName),
    );
  }

  void _openAddContact() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddContactSheet(),
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        titleTextStyle: AeroTextStyles.heading,
        title: Text(title),
        content: Text(body, style: AeroTextStyles.body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
    }
  }

  Future<void> _blockUser(AppUser user) async {
    final ok = await _confirm(
      'Block ${user.displayName}?',
      'They will be moved to your blocked list.',
      'Block',
    );
    if (!ok) return;
    await _runAction(
        () => ref.read(contactsServiceProvider).blockUser(user.uid));
  }

  Future<void> _removeUser(AppUser user) async {
    final ok = await _confirm(
      'Remove ${user.displayName}?',
      'They will be removed from your contact list.',
      'Remove',
    );
    if (!ok) return;
    await _runAction(
        () => ref.read(contactsServiceProvider).removeContact(user.uid));
  }

  Future<void> _unblockUser(AppUser user) async {
    await _runAction(
        () => ref.read(contactsServiceProvider).unblockUser(user.uid));
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(aeroPaletteProvider);
    final buddies = ref.watch(buddyUsersProvider);
    final blockedUsers = ref.watch(blockedUsersProvider);
    final blockedIdSet =
        (ref.watch(blockedIdsProvider).valueOrNull ?? const <String>[])
            .toSet();
    final requests = ref.watch(incomingRequestsProvider).valueOrNull ??
        const <FriendRequest>[];

    final q = _query.trim().toLowerCase();
    bool matches(AppUser u) =>
        q.isEmpty ||
        u.displayName.toLowerCase().contains(q) ||
        u.statusMessage.toLowerCase().contains(q);

    final visible = buddies
        .where((u) => !blockedIdSet.contains(u.uid) && matches(u))
        .toList();

    final children = <Widget>[];

    if (requests.isNotEmpty && q.isEmpty) {
      children.add(_SectionLabel(
        icon: Icons.person_add_alt_1_rounded,
        label: 'Friend requests (${requests.length})',
        color: AeroColors.busy,
      ));
      for (final request in requests) {
        children.add(_RequestTile(request: request));
      }
    }

    for (final status in _groupOrder) {
      final group = visible.where((u) => u.status == status).toList()
        ..sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()));
      if (group.isEmpty) continue;

      final collapsed = _collapsed.contains(status);
      children.add(_GroupHeader(
        label: status.label,
        count: group.length,
        color: status.color,
        expanded: !collapsed,
        onTap: () => setState(() {
          if (collapsed) {
            _collapsed.remove(status);
          } else {
            _collapsed.add(status);
          }
        }),
      ));
      if (!collapsed) {
        for (final user in group) {
          children.add(_BuddyTile(
            user: user,
            onTap: () => _openChat(user),
            onBlock: () => _blockUser(user),
            onRemove: () => _removeUser(user),
          ));
        }
      }
    }

    if (blockedUsers.isNotEmpty && q.isEmpty) {
      children.add(_GroupHeader(
        label: 'Blocked',
        count: blockedUsers.length,
        color: AeroColors.offline,
        expanded: _blockedExpanded,
        onTap: () => setState(() => _blockedExpanded = !_blockedExpanded),
      ));
      if (_blockedExpanded) {
        for (final user in blockedUsers) {
          children.add(_BlockedTile(
            user: user,
            onUnblock: () => _unblockUser(user),
          ));
        }
      }
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: Column(
          children: <Widget>[
            const _ProfileHeader(),
            _buildSearchRow(palette, requests.length),
            Expanded(
              child: SafeArea(
                top: false,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  decoration: AeroDecorations.glassPanel(palette, radius: 22),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: children.isEmpty
                        ? _buildEmptyState(palette, q.isNotEmpty)
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            children: children,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow(AeroPalette palette, int requestCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              style: AeroTextStyles.body,
              decoration: InputDecoration(
                hintText: 'Find a contact…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(
                    color: palette.primaryDark.withOpacity(0.35),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(
                    color: palette.primaryDark.withOpacity(0.35),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: BorderSide(color: palette.accent, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _openAddContact,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: palette.glossGradient,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: palette.primaryDark.withOpacity(0.5),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_add_alt_1_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  if (requestCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            center: Alignment(-0.3, -0.4),
                            colors: <Color>[
                              Color(0xFFFFB199),
                              Color(0xFFE53935),
                            ],
                          ),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          '$requestCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AeroPalette palette, bool searching) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              searching ? Icons.search_off_rounded : Icons.groups_rounded,
              size: 64,
              color: palette.primaryDark.withOpacity(0.55),
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No contacts found' : 'Your contact list is empty',
              style: AeroTextStyles.heading,
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a different name.'
                  : 'Tap the + button to find and add friends.',
              textAlign: TextAlign.center,
              style: AeroTextStyles.statusMessage,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Custom profile "AppBar"
// -----------------------------------------------------------------------------

class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(aeroPaletteProvider);
    final service = ref.watch(firebaseServiceProvider);
    final uid = service.currentUser?.uid;
    final profile =
        uid == null ? null : ref.watch(userProfileProvider(uid)).valueOrNull;

    final name = profile?.displayName ??
        service.currentUser?.displayName ??
        service.currentUser?.email ??
        'Me';
    final status = profile?.status ?? UserStatus.online;
    final statusMessage = profile?.statusMessage ?? '';
    final nowPlaying = profile?.nowPlaying ?? '';

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 12,
        8,
        16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.primaryDark,
            Color.lerp(palette.primaryDark, palette.primaryLight, 0.45)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.8), width: 1.5),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.primaryDark.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -MediaQuery.of(context).padding.top - 12,
              left: -16,
              right: -8,
              height: MediaQuery.of(context).padding.top + 62,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withOpacity(0.28),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _Avatar(
                  name: name,
                  url: profile?.avatarUrl,
                  size: 66,
                  status: status,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PopupMenuButton<UserStatus>(
                        tooltip: 'Change status',
                        padding: EdgeInsets.zero,
                        offset: const Offset(0, 36),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        onSelected: (value) {
                          service.setStatus(value).catchError((_) {});
                        },
                        itemBuilder: (_) => const <UserStatus>[
                          UserStatus.online,
                          UserStatus.away,
                          UserStatus.busy,
                          UserStatus.offline,
                        ]
                            .map(
                              (s) => PopupMenuItem<UserStatus>(
                                value: s,
                                child: Row(
                                  children: <Widget>[
                                    _StatusOrb(status: s, size: 16),
                                    const SizedBox(width: 10),
                                    Text(
                                      s == UserStatus.offline
                                          ? 'Appear offline'
                                          : s.label,
                                      style: AeroTextStyles.body,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AeroTextStyles.title,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '(${status.label})',
                              style: AeroTextStyles.body.copyWith(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down_rounded,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      if (statusMessage.isNotEmpty)
                        Text(
                          statusMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AeroTextStyles.statusMessage.copyWith(
                            color: Colors.white.withOpacity(0.92),
                          ),
                        ),
                      if (nowPlaying.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.music_note_rounded,
                                size: 14,
                                color: Color(0xFFB8F5A8),
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  nowPlaying,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AeroTextStyles.nowPlaying.copyWith(
                                    color: const Color(0xFFB8F5A8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded, color: Colors.white),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await service.signOut();
                    navigator.pushNamedAndRemoveUntil(
                      AppRoutes.gate,
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// List widgets
// -----------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: AeroTextStyles.groupHeader),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool expanded;
  final VoidCallback onTap;

  const _GroupHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
        child: Row(
          children: <Widget>[
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AeroColors.msnBlueDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: <BoxShadow>[
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('$label ($count)', style: AeroTextStyles.groupHeader),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 1,
                color: AeroColors.msnBlueDark.withOpacity(0.18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuddyTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;
  final VoidCallback onBlock;
  final VoidCallback onRemove;

  const _BuddyTile({
    required this.user,
    required this.onTap,
    required this.onBlock,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final showSuffix = user.status == UserStatus.away ||
        user.status == UserStatus.busy;
    final dimmed = user.status == UserStatus.offline;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: <Widget>[
            Opacity(
              opacity: dimmed ? 0.65 : 1.0,
              child: _Avatar(
                name: user.displayName,
                url: user.avatarUrl,
                size: 46,
                status: user.status,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(text: user.displayName),
                        if (showSuffix)
                          TextSpan(
                            text: ' (${user.status.label})',
                            style: AeroTextStyles.statusMessage.copyWith(
                              fontStyle: FontStyle.normal,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AeroTextStyles.buddyName.copyWith(
                      color: dimmed
                          ? AeroColors.textMuted
                          : AeroColors.textDark,
                    ),
                  ),
                  if (user.statusMessage.isNotEmpty)
                    Text(
                      user.statusMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AeroTextStyles.statusMessage,
                    ),
                  if (user.nowPlaying.isNotEmpty)
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.music_note_rounded,
                          size: 13,
                          color: AeroColors.success,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            user.nowPlaying,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AeroTextStyles.nowPlaying,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                color: AeroColors.textMuted,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (value) {
                if (value == 'block') onBlock();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'block',
                  child: Text('Block', style: AeroTextStyles.body),
                ),
                PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('Remove contact', style: AeroTextStyles.body),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedTile extends ConsumerWidget {
  final AppUser user;
  final VoidCallback onUnblock;

  const _BlockedTile({required this.user, required this.onUnblock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: <Widget>[
          Opacity(
            opacity: 0.55,
            child: _Avatar(
              name: user.displayName,
              url: user.avatarUrl,
              size: 40,
              status: null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AeroTextStyles.buddyName.copyWith(
                color: AeroColors.textMuted,
              ),
            ),
          ),
          _MiniGlossButton(
            label: 'Unblock',
            dark: AeroColors.msnBlueDark,
            light: AeroColors.msnBlueLight,
            onTap: onUnblock,
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends ConsumerWidget {
  final FriendRequest request;

  const _RequestTile({required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sender = ref.watch(userProfileProvider(request.fromUid)).valueOrNull;
    final name = sender?.displayName ?? 'Someone';
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(contactsServiceProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.white.withOpacity(0.9),
            const Color(0xFFFFE9CC).withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AeroColors.busy.withOpacity(0.5)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AeroColors.busy.withOpacity(0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          _Avatar(
            name: name,
            url: sender?.avatarUrl,
            size: 42,
            status: null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AeroTextStyles.buddyName,
                ),
                Text('wants to add you', style: AeroTextStyles.statusMessage),
              ],
            ),
          ),
          _MiniGlossButton(
            label: 'Accept',
            dark: const Color(0xFF2E8B3D),
            light: AeroColors.onlineLight,
            onTap: () async {
              try {
                await service.acceptRequest(request);
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not accept request.')),
                );
              }
            },
          ),
          const SizedBox(width: 6),
          _MiniGlossButton(
            label: 'Decline',
            dark: const Color(0xFF7A8794),
            light: AeroColors.offlineLight,
            onTap: () async {
              try {
                await service.declineRequest(request);
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Could not decline request.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Add contact bottom sheet
// -----------------------------------------------------------------------------

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet();

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final TextEditingController _controller = TextEditingController();
  List<AppUser> _results = <AppUser>[];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _controller.text.trim();
    if (text.length < 2) {
      setState(() => _error = 'Type at least 2 characters.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(contactsServiceProvider).searchUsers(text);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Search failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(AppUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(contactsServiceProvider).sendRequest(user.uid);
      messenger.showSnackBar(
        SnackBar(content: Text('Request sent to ${user.displayName}.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send request.')),
      );
    }
  }

  Future<void> _accept(FriendRequest request) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(contactsServiceProvider).acceptRequest(request);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not accept request.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(aeroPaletteProvider);
    final buddyIds =
        (ref.watch(buddyIdsProvider).valueOrNull ?? const <String>[]).toSet();
    final incoming = ref.watch(incomingRequestsProvider).valueOrNull ??
        const <FriendRequest>[];
    final outgoing = ref.watch(outgoingRequestsProvider).valueOrNull ??
        const <FriendRequest>[];

    Widget actionFor(AppUser user) {
      if (buddyIds.contains(user.uid)) {
        return Text('Added', style: AeroTextStyles.nowPlaying);
      }
      final inc = incoming.where((r) => r.fromUid == user.uid).toList();
      if (inc.isNotEmpty) {
        return _MiniGlossButton(
          label: 'Accept',
          dark: const Color(0xFF2E8B3D),
          light: AeroColors.onlineLight,
          onTap: () => _accept(inc.first),
        );
      }
      if (outgoing.any((r) => r.toUid == user.uid)) {
        return Text('Pending', style: AeroTextStyles.statusMessage);
      }
      return _MiniGlossButton(
        label: 'Add',
        dark: palette.primaryDark,
        light: palette.primaryLight,
        onTap: () => _send(user),
      );
    }

    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.78),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.white.withOpacity(0.96),
                  palette.glassTint.withOpacity(0.94),
                ],
              ),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: palette.primaryDark.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Add a contact', style: AeroTextStyles.heading),
                const SizedBox(height: 4),
                Text(
                  'Search by display name or exact e-mail address.',
                  style: AeroTextStyles.statusMessage,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _search(),
                        style: AeroTextStyles.body,
                        decoration: const InputDecoration(
                          hintText: 'Name or e-mail address',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _MiniGlossButton(
                      label: 'Search',
                      dark: palette.primaryDark,
                      light: palette.primaryLight,
                      onTap: _loading ? null : _search,
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: AeroTextStyles.body.copyWith(
                        color: AeroColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_searched && _results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No users found.',
                        style: AeroTextStyles.statusMessage,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      itemBuilder: (_, index) {
                        final user = _results[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: <Widget>[
                              _Avatar(
                                name: user.displayName,
                                url: user.avatarUrl,
                                size: 44,
                                status: user.status,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      user.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AeroTextStyles.buddyName,
                                    ),
                                    if (user.statusMessage.isNotEmpty)
                                      Text(
                                        user.statusMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AeroTextStyles.statusMessage,
                                      ),
                                  ],
                                ),
                              ),
                              actionFor(user),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared small widgets
// -----------------------------------------------------------------------------

class _MiniGlossButton extends StatelessWidget {
  final String label;
  final Color dark;
  final Color light;
  final VoidCallback? onTap;

  const _MiniGlossButton({
    required this.label,
    required this.dark,
    required this.light,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color.lerp(light, Colors.white, 0.55)!,
                light,
                dark,
                Color.lerp(dark, light, 0.3)!,
              ],
              stops: const <double>[0.0, 0.49, 0.5, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.9)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: dark.withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            label,
            style: AeroTextStyles.button.copyWith(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _StatusOrb extends StatelessWidget {
  final UserStatus status;
  final double size;

  const _StatusOrb({required this.status, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: <Color>[Colors.white, status.highlightColor, status.color],
          stops: const <double>[0.0, 0.3, 1.0],
        ),
        border: Border.all(color: Colors.white, width: size > 20 ? 2 : 1.4),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: status.color.withOpacity(0.55),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final UserStatus? status;

  const _Avatar({
    required this.name,
    required this.size,
    this.url,
    this.status,
  });

  Widget _initial() {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AeroColors.msnBlueLight, AeroColors.msnBlueDark],
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ring = status?.color ?? AeroColors.msnBlueMid;
    final hasUrl = url != null && url!.isNotEmpty;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: ring, width: size > 50 ? 3 : 2),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: ring.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: hasUrl
                  ? CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _initial(),
                      errorWidget: (_, __, ___) => _initial(),
                    )
                  : _initial(),
            ),
          ),
          if (status != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: _StatusOrb(status: status!, size: size * 0.34),
            ),
        ],
      ),
    );
  }
}