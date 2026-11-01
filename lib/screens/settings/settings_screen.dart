// lib/screens/settings/settings_screen.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show AppRoutes;
import '../../services/firebase_service.dart';
import '../../theme/aero_theme.dart';
import '../../utils/constants.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();
  final TextEditingController _nowPlayingController = TextEditingController();

  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _nowPlayingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(firebaseServiceProvider).updateProfile(
            displayName: _nameController.text,
            statusMessage: _statusController.text,
            nowPlaying: _nowPlayingController.text,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Your changes have been saved.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not save changes. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await ref.read(firebaseServiceProvider).signOut();
    navigator.pushNamedAndRemoveUntil(AppRoutes.gate, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(aeroPaletteProvider);
    final selectedTheme = ref.watch(aeroThemeIdProvider);
    final service = ref.watch(firebaseServiceProvider);
    final uid = service.currentUser?.uid;
    final profile =
        uid == null ? null : ref.watch(userProfileProvider(uid)).valueOrNull;

    if (profile != null && !_initialized) {
      _nameController.text = profile.displayName;
      _statusController.text = profile.statusMessage;
      _nowPlayingController.text = profile.nowPlaying;
      _initialized = true;
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _buildTopBar(palette),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _GlassSection(
                              palette: palette,
                              title: 'Appearance',
                              icon: Icons.palette_rounded,
                              child: _buildThemeSelector(
                                palette,
                                selectedTheme,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _GlassSection(
                              palette: palette,
                              title: 'Profile',
                              icon: Icons.person_rounded,
                              child: _buildProfileFields(),
                            ),
                            const SizedBox(height: 16),
                            _GlassSection(
                              palette: palette,
                              title: 'Now playing',
                              icon: Icons.music_note_rounded,
                              child: _buildNowPlaying(palette),
                            ),
                            const SizedBox(height: 22),
                            _GlossButton(
                              palette: palette,
                              label: 'Save changes',
                              loading: _saving,
                              onPressed: _saving ? null : _save,
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton.icon(
                                onPressed: _saving ? null : _signOut,
                                icon: const Icon(
                                  Icons.logout_rounded,
                                  color: Colors.white,
                                ),
                                label: Text(
                                  'Sign out',
                                  style: AeroTextStyles.bodyBold.copyWith(
                                    color: Colors.white,
                                    shadows: const <Shadow>[
                                      Shadow(
                                        color: Color(0x66000000),
                                        blurRadius: 3,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AeroPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white.withOpacity(0.95),
                    palette.primaryLight.withOpacity(0.7),
                  ],
                ),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.primaryDark.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: palette.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text('Settings', style: AeroTextStyles.title),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(AeroPalette current, AeroThemeId selected) {
    return Row(
      children: AeroPalettes.all.map((p) {
        final isSelected = p.id == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () =>
                  ref.read(aeroThemeIdProvider.notifier).setTheme(p.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 112,
                decoration: BoxDecoration(
                  gradient: p.backgroundGradient,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white54,
                    width: isSelected ? 3 : 1.2,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: p.primaryDark
                          .withOpacity(isSelected ? 0.65 : 0.25),
                      blurRadius: isSelected ? 14 : 6,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: <Widget>[
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.white.withOpacity(0.55),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              center: Alignment(-0.3, -0.4),
                              colors: <Color>[
                                AeroColors.onlineLight,
                                AeroColors.online,
                              ],
                            ),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 10,
                      child: Text(
                        p.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: AeroTextStyles.bodyBold.copyWith(
                          fontSize: 12,
                          color: p.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProfileFields() {
    return Column(
      children: <Widget>[
        TextFormField(
          controller: _nameController,
          enabled: !_saving,
          textInputAction: TextInputAction.next,
          maxLength: AppConstants.maxDisplayNameLength,
          style: AeroTextStyles.body,
          validator: (value) {
            final text = (value ?? '').trim();
            if (text.isEmpty) return 'Display name cannot be empty.';
            if (text.length < 2) return 'Display name is too short.';
            return null;
          },
          decoration: const InputDecoration(
            labelText: 'Display name',
            counterText: '',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _statusController,
          enabled: !_saving,
          textInputAction: TextInputAction.next,
          maxLength: AppConstants.maxStatusMessageLength,
          style: AeroTextStyles.body,
          decoration: const InputDecoration(
            labelText: 'Personal message',
            counterText: '',
            prefixIcon: Icon(Icons.chat_bubble_rounded),
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlaying(AeroPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          controller: _nowPlayingController,
          enabled: !_saving,
          textInputAction: TextInputAction.done,
          maxLength: AppConstants.maxStatusMessageLength,
          style: AeroTextStyles.body,
          decoration: InputDecoration(
            labelText: 'Artist - Title',
            counterText: '',
            prefixIcon: const Icon(Icons.library_music_rounded),
            suffixIcon: IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _nowPlayingController.clear(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Preview', style: AeroTextStyles.groupHeader),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nowPlayingController,
          builder: (context, value, _) {
            final text = value.text.trim();
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFF3A3F47), Color(0xFF14171B)],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8A939E), width: 1.2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.graphic_eq_rounded,
                    color: Color(0xFF6DFF5A),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text.isEmpty
                          ? 'Nothing playing'
                          : '\u266B $text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AeroTextStyles.body.copyWith(
                        color: text.isEmpty
                            ? const Color(0xFF7D8791)
                            : const Color(0xFF6DFF5A),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Shown to your contacts under your name. Leave empty to hide it.',
          style: AeroTextStyles.statusMessage,
        ),
      ],
    );
  }
}

class _GlassSection extends StatelessWidget {
  final AeroPalette palette;
  final String title;
  final IconData icon;
  final Widget child;

  const _GlassSection({
    required this.palette,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: AeroDecorations.glassPanel(palette, radius: 22),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: palette.glossGradient,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Icon(icon, size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: AeroTextStyles.heading),
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _GlossButton extends StatefulWidget {
  final AeroPalette palette;
  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  const _GlossButton({
    required this.palette,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  State<_GlossButton> createState() => _GlossButtonState();
}

class _GlossButtonState extends State<_GlossButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled || widget.loading ? 1.0 : 0.6,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          scale: _pressed ? 0.97 : 1.0,
          child: Container(
            height: 52,
            decoration: AeroDecorations.glossButton(
              widget.palette,
              radius: 26,
              pressed: _pressed,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  top: 3,
                  left: 10,
                  right: 10,
                  height: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Colors.white.withOpacity(0.75),
                          Colors.white.withOpacity(0.08),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Text(widget.label, style: AeroTextStyles.button),
              ],
            ),
          ),
        ),
      ),
    );
  }
}