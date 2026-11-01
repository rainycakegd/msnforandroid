// lib/screens/auth/login_screen.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show AppRoutes;
import '../../services/firebase_service.dart';
import '../../theme/aero_theme.dart';
import '../../utils/constants.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _rememberEmail = true;
  String? _error;
  UserStatus _selectedStatus = UserStatus.online;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(AppConstants.prefLastEmail);
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() => _emailController.text = saved);
      }
    } catch (_) {
      // Ignore local storage errors.
    }
  }

  Future<void> _persistEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberEmail) {
        await prefs.setString(
          AppConstants.prefLastEmail,
          _emailController.text.trim(),
        );
      } else {
        await prefs.remove(AppConstants.prefLastEmail);
      }
    } catch (_) {
      // Ignore local storage errors.
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final service = ref.read(firebaseServiceProvider);
    try {
      await service.signIn(
        email: _emailController.text,
        password: _passwordController.text,
        initialStatus: _selectedStatus,
      );
      await _persistEmail();

      if (!mounted) return;
      // If this screen was pushed on top of the gate, return to the gate so
      // the auth state can route to the buddy list.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.gate,
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = FirebaseService.authErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _emailController.text);
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titleTextStyle: AeroTextStyles.heading,
          title: const Text('Reset password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Enter your e-mail address and we will send you a link to '
                'reset your password.',
                style: AeroTextStyles.body,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'E-mail address'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Send link'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (email == null || email.isEmpty || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(firebaseServiceProvider).sendPasswordReset(email);
      messenger.showSnackBar(
        const SnackBar(content: Text('Password reset e-mail sent.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(FirebaseService.authErrorMessage(e))),
      );
    }
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Please enter your e-mail address.';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(text)) return 'That e-mail address does not look right.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password.';
    if (value.length < 6) return 'Password must be at least 6 characters.';
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
            const _AeroBubble(top: 60, left: -30, size: 130),
            const _AeroBubble(top: 170, right: -40, size: 160),
            const _AeroBubble(bottom: 120, left: 20, size: 90),
            const _AeroBubble(bottom: -30, right: 40, size: 140),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _buildHeader(palette),
                        const SizedBox(height: 22),
                        _buildGlassForm(palette),
                        const SizedBox(height: 18),
                        _buildFooter(palette),
                      ],
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

  Widget _buildHeader(AeroPalette palette) {
    return Column(
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white,
                    palette.primaryLight,
                    Color.lerp(palette.primaryLight, palette.primaryDark, 0.4)!,
                  ],
                ),
                border: Border.all(
                  color: _selectedStatus.color,
                  width: 4,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.primaryDark.withOpacity(0.5),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: _selectedStatus.color.withOpacity(0.35),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipOval(
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Icon(
                      Icons.person_rounded,
                      size: 66,
                      color: palette.primaryDark.withOpacity(0.85),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 50,
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
              right: 2,
              bottom: 4,
              child: _GlossStatusDot(status: _selectedStatus, size: 28),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Sign in to', style: AeroTextStyles.title.copyWith(fontSize: 16)),
        Text(AppConstants.appName, style: AeroTextStyles.splashTitle),
      ],
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
              // Glossy top highlight.
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
                      Text('Status when signing in',
                          style: AeroTextStyles.groupHeader),
                      const SizedBox(height: 8),
                      _buildStatusPicker(palette),
                      const SizedBox(height: 18),
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
                        textInputAction: TextInputAction.done,
                        validator: _validatePassword,
                        onFieldSubmitted: (_) => _submit(),
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
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: Checkbox(
                              value: _rememberEmail,
                              activeColor: palette.primaryDark,
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(
                                        () => _rememberEmail = v ?? true,
                                      ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Remember my e-mail address',
                              style: AeroTextStyles.body
                                  .copyWith(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 10),
                        _buildErrorBanner(_error!),
                      ],
                      const SizedBox(height: 16),
                      _GlossButton(
                        palette: palette,
                        label: 'Sign in',
                        loading: _loading,
                        onPressed: _loading ? null : _submit,
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: Text(
                            'Forgot your password?',
                            style: AeroTextStyles.body.copyWith(
                              color: palette.primaryDark,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
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
        ),
      ),
    );
  }

  Widget _buildStatusPicker(AeroPalette palette) {
    const options = <UserStatus>[
      UserStatus.online,
      UserStatus.away,
      UserStatus.busy,
    ];

    return Row(
      children: options.map((status) {
        final selected = status == _selectedStatus;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: _loading ? null : () => setState(() => _selectedStatus = status),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: selected
                        ? <Color>[Colors.white, status.highlightColor]
                        : <Color>[
                            Colors.white.withOpacity(0.7),
                            Colors.white.withOpacity(0.3),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? status.color
                        : palette.primaryDark.withOpacity(0.2),
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: selected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: status.color.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : const <BoxShadow>[],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _GlossStatusDot(status: status, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      status.label,
                      style: AeroTextStyles.body.copyWith(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
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

  Widget _buildFooter(AeroPalette palette) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          'Don\'t have an account? ',
          style: AeroTextStyles.body.copyWith(
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
        GestureDetector(
          onTap: _loading
              ? null
              : () => Navigator.of(context).pushNamed(AppRoutes.register),
          child: Text(
            'Sign up',
            style: AeroTextStyles.bodyBold.copyWith(
              color: Colors.white,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white,
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
      ],
    );
  }
}

/// Glossy two-tone pill button with a hard highlight across the top half.
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

/// Classic glossy status orb (Online / Away / Busy / Offline).
class _GlossStatusDot extends StatelessWidget {
  final UserStatus status;
  final double size;

  const _GlossStatusDot({required this.status, required this.size});

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
          colors: <Color>[
            Colors.white,
            status.highlightColor,
            status.color,
          ],
          stops: const <double>[0.0, 0.3, 1.0],
        ),
        border: Border.all(color: Colors.white, width: size > 20 ? 2 : 1.2),
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

/// Decorative translucent Aero bubble for the background.
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