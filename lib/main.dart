// lib/main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/buddy_list/buddy_list_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'theme/aero_theme.dart';
import 'utils/constants.dart';

/// Named routes used across the app.
class AppRoutes {
  static const String gate = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String buddies = '/buddies';
  static const String chat = '/chat';
  static const String settings = '/settings';
}

/// Arguments passed to [AppRoutes.chat].
class ChatRouteArgs {
  final String peerId;
  final String peerName;

  const ChatRouteArgs({required this.peerId, required this.peerName});
}

/// Streams the Firebase auth state (signed in / signed out).
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Uses android/app/google-services.json for configuration.
  await Firebase.initializeApp();

  // Offline caching: Firestore keeps a local copy of data and queues writes.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  runApp(const ProviderScope(child: AeroMessengerApp()));
}

class AeroMessengerApp extends ConsumerWidget {
  const AeroMessengerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(aeroPaletteProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AeroTheme.build(palette),
      initialRoute: AppRoutes.gate,
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.gate:
        return _fade(const AuthGate(), settings);
      case AppRoutes.login:
        return _fade(const LoginScreen(), settings);
      case AppRoutes.register:
        return _fade(const RegisterScreen(), settings);
      case AppRoutes.buddies:
        return _fade(const BuddyListScreen(), settings);
      case AppRoutes.settings:
        return _fade(const SettingsScreen(), settings);
      case AppRoutes.chat:
        final args = settings.arguments;
        if (args is ChatRouteArgs) {
          return _fade(
            ChatScreen(peerId: args.peerId, peerName: args.peerName),
            settings,
          );
        }
        return _fade(const AuthGate(), settings);
      default:
        return _fade(const AuthGate(), settings);
    }
  }

  PageRouteBuilder<dynamic> _fade(Widget page, RouteSettings settings) {
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }
}

/// Decides between the login screen and the buddy list based on auth state.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateChangesProvider);

    return authState.when(
      data: (user) =>
          user == null ? const LoginScreen() : const BuddyListScreen(),
      loading: () => const _SplashScreen(),
      error: (error, _) => _SplashScreen(message: 'Connection error: $error'),
    );
  }
}

class _SplashScreen extends ConsumerWidget {
  final String? message;

  const _SplashScreen({this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(aeroPaletteProvider);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              palette.primaryDark,
              palette.primaryLight,
              Colors.white,
            ],
            stops: const <double>[0.0, 0.65, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white.withOpacity(0.95),
                      palette.primaryLight.withOpacity(0.6),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.9),
                    width: 2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.primaryDark.withOpacity(0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  size: 48,
                  color: palette.primaryDark,
                ),
              ),
              const SizedBox(height: 24),
              Text(AppConstants.appName, style: AeroTextStyles.splashTitle),
              const SizedBox(height: 16),
              if (message == null)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: AeroTextStyles.body.copyWith(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}