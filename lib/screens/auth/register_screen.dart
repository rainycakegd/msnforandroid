// lib/screens/auth/register_screen.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../main.dart' show AppRoutes;
import '../../services/firebase_service.dart';
import '../../theme/aero_theme.dart';
import '../../utils/constants.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _avatar;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _statusController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (picked != null && mounted) {
        setState(() => _avatar = File(picked.path));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open your photo library.');
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ref.read(firebaseServiceProvider).register(
            email: _emailController.text,
            password: _passwordController.text,
            displayName: _nameController.text,
            statusMessage: _statusController.text,
            avatar: _avatar,
          );
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.gate,
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = FirebaseService.authErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _validateName(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Please choose a display name.';
    if (text.length < 2) return 'Display name is too short.';
    return null;
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Please enter your e-mail address.';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(text)) return 'That e-mail address does not look right.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please choose a password.';
    if (value.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  String? _validateConfirm(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(aeroPaletteProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(gradient: palette.backgroundGradient),
        child: Stack(
          children: <Widget>[
            const _AeroBubble(top: 90, right: -40, size: 150),
            const _AeroBubble(top: 300, left: -50, size: 120),
            const _AeroBubble(bottom: 60, right: 10, size: 100),
            SafeArea(
              child: Column(
                children: <Widget>[
                  _buildTopBar(palette),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _buildGlassForm(palette),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            onTap: _loading ? null : () => Navigator.of(context).maybePop(),
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
          Text('Create your account', style: AeroTextStyles.title),
        ],
      ),
    );
  }

  Widget _buildGlassForm(AeroPalette palette) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: AeroDecorations.glassPanel(palette, radius: 24),
          child: Stack(
            children: <Widget>[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 70,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.white.withOpacity(0.7),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildAvatarPicker(palette),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        enabled: !_loading,
                        textInputAction: TextInputAction.next,
                        maxLength: AppConstants.maxDisplayNameLength,
                        validator: _validateName,
                        style: AeroTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          counterText: '',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _statusController,
                        enabled: !_loading,
                        textInputAction: TextInputAction.next,
                        maxLength: AppConstants.maxStatusMessageLength,
                        style: AeroTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Personal message (optional)',
                          counterText: '',
                          prefixIcon: Icon(Icons.chat_bubble_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        enabled: !_loading,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        validator: _validateEmail,
                        style: AeroTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'E-mail address',
                          prefixIcon: Icon(Icons.alternate_email_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !_loading,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.next,
                        validator: _validatePassword,
                        style: AeroTextStyles.body,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        enabled: !_loading,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        validator: _validateConfirm,
                        onFieldSubmitted: (_) => _submit(),
                        style: AeroTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _buildErrorBanner(_error!),
                      ],
                      const SizedBox(height: 20),
                      _GlossButton(
                        palette: palette,
                        label: 'Create account',
                        loading: _loading,
                        onPressed: _loading ? null : _submit,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            'Already have an account? ',
                            style: AeroTextStyles.body,
                          ),
                          GestureDetector(
                            onTap: _loading
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            child: Text(
                              'Sign in',
                              style: AeroTextStyles.bodyBold.copyWith(
                                color: palette.primaryDark,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(AeroPalette palette) {
    return Column(
      children: <Widget>[
        GestureDetector(
          onTap: _loading ? null : _pickAvatar,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.white,
                      palette.primaryLight,
                      Color.lerp(
                          palette.primaryLight, palette.primaryDark, 0.4)!,
                    ],
                  ),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: palette.primaryDark.withOpacity(0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: _avatar != null
                      ? Image.file(_avatar!, fit: BoxFit.cover)
                      : Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Icon(
                              Icons.person_rounded,
                              size: 68,
                              color: palette.primaryDark.withOpacity(0.85),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 52,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: <Color>[
                                      Colors.white.withOpacity(0.8),
                                      Colors.white.withOpacity(0.05),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              Positioned(
                right: -2,
                bottom: 2,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: palette.glossGradient,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: palette.primaryDark.withOpacity(0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _avatar == null ? 'Tap to choose a picture' : 'Tap to change picture',
          style: AeroTextStyles.statusMessage,
        ),
        if (_avatar != null)
          GestureDetector(
            onTap: _loading ? null : () => setState(() => _avatar = null),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Remove picture',
                style: AeroTextStyles.body.copyWith(
                  fontSize: 12,
                  color: AeroColors.error,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFFFFE3E3), Color(0xFFFFBFBF)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AeroColors.error.withOpacity(0.7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AeroColors.error.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_rounded, color: AeroColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AeroTextStyles.body.copyWith(
                fontSize: 13,
                color: const Color(0xFF7A1E1E),
              ),
            ),
          ),
        ],
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

class _AeroBubble extends StatelessWidget {
  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;

  const _AeroBubble({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.5),
              radius: 1.0,
              colors: <Color>[
                Colors.white.withOpacity(0.55),
                Colors.white.withOpacity(0.12),
                Colors.white.withOpacity(0.04),
              ],
              stops: const <double>[0.0, 0.6, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}