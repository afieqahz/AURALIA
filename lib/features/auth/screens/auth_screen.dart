import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/features/home/screens/main_layout.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool acceptTerms = false;
  int _pageIndex = 0;

  final _loginFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final PageController _pageController = PageController();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    final formKey = isLogin ? _loginFormKey : _signUpFormKey;
    if (formKey.currentState?.validate() == true) {
      if (!isLogin && !acceptTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You must accept the Terms and Conditions to proceed.',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final state = AuraliaScope.of(context);
      final success = isLogin
          ? await state.signIn(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            )
          : await state.signUp(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              name: _nameController.text.trim(),
            );

      if (!mounted) {
        return;
      }

      if (!success) {
        final message =
            state.errorMessage ?? 'Authentication failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: message.startsWith('Account created')
                ? const Color(0xFF4A154B)
                : Colors.redAccent,
          ),
        );
        if (!isLogin && message.startsWith('Account created')) {
          setState(() {
            isLogin = true;
            _passwordController.clear();
            _confirmPasswordController.clear();
            acceptTerms = false;
          });
        }
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLogin ? 'Welcome back!' : 'Account registered successfully!',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: const Color(0xFF4A154B),
          duration: const Duration(seconds: 1),
        ),
      );

      // Transition to Main Layout after login/signup
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainLayout()),
      );
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  Future<void> _showForgotPasswordDialog() async {
    final controller = TextEditingController(text: _emailController.text);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Reset password',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF38143E),
          ),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: _validateEmail,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) {
                return;
              }
              final state = AuraliaScope.of(context);
              final success = await state.resetPassword(
                email: controller.text.trim(),
              );
              if (!dialogContext.mounted || !mounted) {
                return;
              }
              Navigator.of(dialogContext).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'Password reset instructions were sent to your email.'
                        : state.errorMessage ??
                              'Unable to send password reset instructions.',
                  ),
                  backgroundColor: success
                      ? const Color(0xFF4A154B)
                      : Colors.redAccent,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5A2C62),
            ),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showTermsDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Terms and Conditions',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF38143E),
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'AURALIA provides mood tracking and music recommendations for personal wellbeing support. It is not a medical or diagnostic service. Your account details, selected moods, playlists, and favourites are used to provide app features and analytics. Spotify playback is governed by Spotify account requirements and terms.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.45,
              color: Colors.black54,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Close',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF5A2C62),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: _AuraliaAuthBackdrop(
        child: SafeArea(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _pageIndex = index;
                if (index == 1) {
                  isLogin = true;
                } else if (index == 2) {
                  isLogin = false;
                }
              });
            },
            children: [
              _WelcomeAuthPage(
                pageIndex: _pageIndex,
                onStart: () => _goToAuthPage(loginMode: true),
                onCreate: () => _goToAuthPage(loginMode: false),
              ),
              _AuthFormPage(
                formKey: _loginFormKey,
                isLogin: true,
                pageIndex: _pageIndex,
                title: 'Welcome back',
                subtitle: 'Continue your mood playlists and listening insights.',
                fields: _loginFields(state),
                onSubmit: _handleSubmit,
                onSwitch: () => _goToAuthPage(loginMode: false),
                switchText: "Don't have an account?",
                switchAction: 'Create an account',
                isBusy: state.isBusy,
              ),
              _AuthFormPage(
                formKey: _signUpFormKey,
                isLogin: false,
                pageIndex: _pageIndex,
                title: 'Welcome to AURALIA',
                subtitle: 'Create your personal mood-aware music space.',
                fields: _signUpFields(state),
                onSubmit: _handleSubmit,
                onSwitch: () => _goToAuthPage(loginMode: true),
                switchText: 'Already have an account?',
                switchAction: 'Log in',
                isBusy: state.isBusy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginFields(dynamic state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassInputField(
          label: 'Email',
          hint: 'name@email.com',
          controller: _emailController,
          validator: _validateEmail,
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
        ),
        const SizedBox(height: 14),
        _GlassInputField(
          label: 'Password',
          hint: 'Enter your password',
          isObscure: true,
          controller: _passwordController,
          icon: Icons.lock_outline_rounded,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _handleSubmit(),
          validator: _validatePassword,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: state.isBusy ? null : _showForgotPasswordDialog,
            child: Text(
              'Forgot password?',
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _signUpFields(dynamic state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassInputField(
          label: 'Email',
          hint: 'name@email.com',
          controller: _emailController,
          validator: _validateEmail,
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
        ),
        const SizedBox(height: 14),
        _GlassInputField(
          label: 'Name',
          hint: 'Enter your name',
          controller: _nameController,
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Name is required';
            }
            if (value.trim().length < 2) {
              return 'Name must be at least 2 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        _GlassInputField(
          label: 'Password',
          hint: 'Enter your password',
          isObscure: true,
          controller: _passwordController,
          icon: Icons.lock_outline_rounded,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
          validator: _validatePassword,
        ),
        const SizedBox(height: 14),
        _GlassInputField(
          label: 'Confirm Password',
          hint: 'Re-enter your password',
          isObscure: true,
          controller: _confirmPasswordController,
          icon: Icons.verified_user_outlined,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onFieldSubmitted: (_) => _handleSubmit(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please confirm your password';
            }
            if (value != _passwordController.text) {
              return 'Passwords do not match';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: acceptTerms,
                onChanged: state.isBusy
                    ? null
                    : (val) => setState(() => acceptTerms = val ?? false),
                activeColor: const Color(0xFF4A154B),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _showTermsDialog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to AURALIA\'s ',
                      children: const [
                        TextSpan(
                          text: 'Terms and Conditions',
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _switchMode(bool loginMode) {
    setState(() {
      isLogin = loginMode;
      _loginFormKey.currentState?.reset();
      _signUpFormKey.currentState?.reset();
      _emailController.clear();
      _nameController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      acceptTerms = false;
    });
  }

  void _goToAuthPage({required bool loginMode}) {
    _switchMode(loginMode);
    _pageController.animateToPage(
      loginMode ? 1 : 2,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }
}

class _AuraliaAuthBackdrop extends StatefulWidget {
  const _AuraliaAuthBackdrop({required this.child});

  final Widget child;

  @override
  State<_AuraliaAuthBackdrop> createState() => _AuraliaAuthBackdropState();
}

class _AuraliaAuthBackdropState extends State<_AuraliaAuthBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.8 + value * 0.35, -1),
              end: Alignment(0.8 - value * 0.25, 1),
              colors: const [
                Color(0xFF05040B),
                Color(0xFF1C0A2C),
                Color(0xFF4A154B),
                Color(0xFF081832),
              ],
              stops: const [0, 0.34, 0.7, 1],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 40 + value * 18,
                right: -82,
                child: _GlowOrb(
                  size: 210,
                  color: const Color(0xFFE599C5).withValues(alpha: 0.28),
                ),
              ),
              Positioned(
                bottom: 70 - value * 16,
                left: -95,
                child: _GlowOrb(
                  size: 230,
                  color: const Color(0xFF6E2D72).withValues(alpha: 0.34),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: 80,
            spreadRadius: 40,
          ),
        ],
      ),
    );
  }
}

class _WelcomeAuthPage extends StatelessWidget {
  const _WelcomeAuthPage({
    required this.pageIndex,
    required this.onStart,
    required this.onCreate,
  });

  final int pageIndex;
  final VoidCallback onStart;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AuthTopBar(pageIndex: pageIndex),
          const Spacer(),
          Center(
            child: _FloatingAuraliaMark(size: 178),
          ),
          const SizedBox(height: 36),
          Text(
            'Discover music\nthat meets your mood',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 31,
              height: 1.12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'AURALIA shapes Spotify playlists through mood check-ins, ISO-Principle flow, and listening insights.',
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _GradientAuthButton(
                  label: "Let's go",
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onStart,
                ),
              ),
              const SizedBox(width: 12),
              _CircleAuthButton(
                icon: Icons.person_add_alt_1_rounded,
                onPressed: onCreate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthFormPage extends StatelessWidget {
  const _AuthFormPage({
    required this.formKey,
    required this.isLogin,
    required this.pageIndex,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.onSubmit,
    required this.onSwitch,
    required this.switchText,
    required this.switchAction,
    required this.isBusy,
  });

  final GlobalKey<FormState> formKey;
  final bool isLogin;
  final int pageIndex;
  final String title;
  final String subtitle;
  final Widget fields;
  final VoidCallback onSubmit;
  final VoidCallback onSwitch;
  final String switchText;
  final String switchAction;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height -
              MediaQuery.paddingOf(context).top -
              MediaQuery.paddingOf(context).bottom -
              46,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AuthTopBar(pageIndex: pageIndex),
            const SizedBox(height: 18),
            Center(child: _FloatingAuraliaMark(size: isLogin ? 132 : 118)),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fields,
                  const SizedBox(height: 18),
                  _GradientAuthButton(
                    label: isBusy
                        ? 'Please wait'
                        : isLogin
                            ? 'Login'
                            : 'Sign Up',
                    icon: isLogin
                        ? Icons.login_rounded
                        : Icons.person_add_alt_1_rounded,
                    isBusy: isBusy,
                    onPressed: isBusy ? null : onSubmit,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                Text(
                  '$switchText ',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                  ),
                ),
                GestureDetector(
                  onTap: isBusy ? null : onSwitch,
                  child: Text(
                    switchAction,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'AURALIA',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const Spacer(),
        _PageDots(activeIndex: pageIndex),
      ],
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: active ? 20 : 7,
          height: 7,
          margin: const EdgeInsets.only(left: 5),
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}

class _FloatingAuraliaMark extends StatefulWidget {
  const _FloatingAuraliaMark({required this.size});

  final double size;

  @override
  State<_FloatingAuraliaMark> createState() => _FloatingAuraliaMarkState();
}

class _FloatingAuraliaMarkState extends State<_FloatingAuraliaMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -7 * _controller.value),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE599C5).withValues(
                    alpha: 0.26 + _controller.value * 0.12,
                  ),
                  blurRadius: 42,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Image.asset(
        'assets/auralia_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.headphones_rounded,
          size: 92,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _GradientAuthButton extends StatelessWidget {
  const _GradientAuthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A1BD8), Color(0xFFB746D1), Color(0xFFFF92E8)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE599C5).withValues(alpha: 0.24),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Icon(icon, color: Colors.white),
          label: Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleAuthButton extends StatelessWidget {
  const _CircleAuthButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton.filled(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFE030B7),
          foregroundColor: Colors.white,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _GlassInputField extends StatefulWidget {
  const _GlassInputField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.validator,
    required this.icon,
    this.isObscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onFieldSubmitted,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final IconData icon;
  final bool isObscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<_GlassInputField> createState() => _GlassInputFieldState();
}

class _GlassInputFieldState extends State<_GlassInputField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.isObscure;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          obscureText: widget.isObscure && _obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          onFieldSubmitted: widget.onFieldSubmitted,
          autocorrect: !widget.isObscure,
          enableSuggestions: !widget.isObscure,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 12,
            ),
            prefixIcon: Icon(
              widget.icon,
              color: Colors.white.withValues(alpha: 0.62),
              size: 19,
            ),
            suffixIcon: widget.isObscure
                ? IconButton(
                    tooltip: _obscureText ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() => _obscureText = !_obscureText);
                    },
                    icon: Icon(
                      _obscureText
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white.withValues(alpha: 0.62),
                      size: 18,
                    ),
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.10),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            errorStyle: GoogleFonts.poppins(
              color: const Color(0xFFFFB6C9),
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFE599C5)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFFF92A8)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: Color(0xFFFF92A8), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({required this.isLogin});

  final bool isLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF38143E), Color(0xFF6E2D72)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AURALIA',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Mood-aware music',
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            isLogin
                ? 'Welcome back to your soundspace.'
                : 'Create your personal listening space.',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 25,
              height: 1.14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isLogin
                ? 'Sign in to continue your mood playlists, favourites, and listening insights.'
                : 'Track your moods, generate ISO-Principle playlists, and save the mixes that help.',
            style: GoogleFonts.poppins(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          const Row(
            children: [
              _HeroPill(icon: Icons.music_note_rounded, label: 'Spotify'),
              SizedBox(width: 8),
              _HeroPill(icon: Icons.favorite_rounded, label: 'Wellness'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeSwitch extends StatelessWidget {
  const _AuthModeSwitch({
    required this.isLogin,
    required this.enabled,
    required this.onChanged,
  });

  final bool isLogin;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF6EEF7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AuthModeButton(
              label: 'Log in',
              selected: isLogin,
              onTap: enabled ? () => onChanged(true) : null,
            ),
          ),
          Expanded(
            child: _AuthModeButton(
              label: 'Sign up',
              selected: !isLogin,
              onTap: enabled ? () => onChanged(false) : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: selected ? const Color(0xFF4A154B) : Colors.black45,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AuthFooter extends StatelessWidget {
  const _AuthFooter({
    required this.isLogin,
    required this.enabled,
    required this.onTap,
  });

  final bool isLogin;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          isLogin ? "Don't have an account? " : 'Already have an account? ',
          style: GoogleFonts.poppins(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 13,
          ),
        ),
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Text(
            isLogin ? 'Create one' : 'Log in',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
