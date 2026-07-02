import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:auralia_app/core/config/app_config.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/core/services/spotify_playback_service.dart';
import 'package:auralia_app/core/widgets/floating_bubbles.dart';
import 'package:auralia_app/features/auth/screens/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SpotifyPlaybackService _spotify = SpotifyPlaybackService();
  bool _isConnectingSpotify = false;

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    final user = state.currentUser;
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'AURALIA User';
    final email = user?.email ?? 'No email available';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF38143E),
            ),
          ),
          const SizedBox(height: 20),
          _ProfileHeader(
            name: name,
            email: email,
          ),
          const SizedBox(height: 28),
          const _SectionLabel('Account'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _ActionRow(
                icon: Icons.person_outline_rounded,
                title: 'Display name',
                subtitle: name,
                onTap: state.isBusy ? () {} : () => _editProfile(state, name),
              ),
              _ProfileRow(
                icon: Icons.mail_outline_rounded,
                title: 'Email address',
                subtitle: email,
              ),
              _ActionRow(
                icon: Icons.lock_outline_rounded,
                title: 'Change password',
                subtitle: 'Update your account password',
                onTap: state.isBusy ? () {} : () => _changePassword(state),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('Connections'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _ConnectionRow(
                icon: Icons.cloud_done_outlined,
                title: 'AURALIA account',
                subtitle: AppConfig.hasSupabaseConfig
                    ? 'Mood history and playlists are synced'
                    : 'Local demo mode',
                connected: AppConfig.hasSupabaseConfig,
              ),
              _ConnectionRow(
                icon: Icons.music_note_rounded,
                title: 'Spotify',
                subtitle: _spotify.isConnected
                    ? 'Connected for full-track playback'
                    : _spotify.isConfigured
                    ? 'Connect to play full Spotify tracks'
                    : 'Spotify playback is not configured',
                connected: _spotify.isConnected,
                actionLabel: _spotify.isConfigured
                    ? _spotify.isConnected
                          ? 'Disconnect'
                          : 'Connect'
                    : null,
                isBusy: _isConnectingSpotify,
                onAction: _spotify.isConfigured ? _toggleSpotify : null,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionLabel('AURALIA'),
          const SizedBox(height: 10),
          _SettingsGroup(
            children: [
              _ActionRow(
                icon: Icons.info_outline_rounded,
                title: 'About AURALIA',
                subtitle: 'Mood-aware music and the ISO-Principle',
                onTap: () => _showAboutDialog(context),
              ),
              _ActionRow(
                icon: Icons.shield_outlined,
                title: 'Data and privacy',
                subtitle: 'How your account data is used',
                onTap: () => _showPrivacyDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SettingsGroup(
            children: [
              _DangerActionRow(
                icon: Icons.delete_outline_rounded,
                title: 'Delete account',
                subtitle: 'Permanently remove your account and AURALIA data',
                onTap: state.isBusy ? () {} : () => _confirmDeleteAccount(state),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: state.isBusy ? null : () => _confirmLogout(context),
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                'Log out',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8C3343),
                side: const BorderSide(color: Color(0xFFD5AAB1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'AURALIA 1.0.0',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.black38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSpotify() async {
    if (_isConnectingSpotify) {
      return;
    }

    final wasConnected = _spotify.isConnected;
    setState(() => _isConnectingSpotify = true);
    if (wasConnected) {
      await _spotify.disconnect();
    } else {
      await _spotify.connect();
    }

    if (!mounted) {
      return;
    }
    setState(() => _isConnectingSpotify = false);

    final connected = _spotify.isConnected;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          connected
              ? 'Spotify connected.'
              : wasConnected
              ? 'Spotify disconnected.'
              : _spotify.lastError ?? 'Unable to connect Spotify.',
        ),
        backgroundColor: connected
            ? const Color(0xFF4A154B)
            : const Color(0xFF755477),
      ),
    );
  }

  Future<void> _editProfile(
    AuraliaState state,
    String currentName,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) =>
          _EditProfileDialog(initialName: currentName),
    );

    if (newName == null || newName == currentName || !mounted) {
      return;
    }

    final success = await state.updateProfile(name: newName);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Profile updated.'
              : state.errorMessage ?? 'Unable to update profile.',
        ),
        backgroundColor: success
            ? const Color(0xFF4A154B)
            : Colors.redAccent,
      ),
    );
  }

  Future<void> _changePassword(AuraliaState state) async {
    final newPassword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ChangePasswordDialog(),
    );

    if (newPassword == null || !mounted) {
      return;
    }

    final success = await state.changePassword(newPassword: newPassword);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Password changed successfully.'
              : state.errorMessage ?? 'Unable to change password.',
        ),
        backgroundColor: success
            ? const Color(0xFF4A154B)
            : Colors.redAccent,
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Log out?',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF38143E),
          ),
        ),
        content: Text(
          'You will need to sign in again to access your saved mood history and playlists.',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8C3343),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !context.mounted) {
      return;
    }

    final state = AuraliaScope.of(context);
    await _spotify.disconnect();
    await state.signOut();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _confirmDeleteAccount(AuraliaState state) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _DeleteAccountDialog(),
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    await _spotify.disconnect();
    final success = await state.deleteAccount();
    if (!mounted) {
      return;
    }

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.errorMessage ?? 'Unable to delete account right now.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _showAboutDialog(BuildContext context) {
    return _showInformationDialog(
      context,
      title: 'About AURALIA',
      icon: Icons.music_note_rounded,
      text:
          'AURALIA generates mood-aware Spotify playlists using rule-based recommendations and the ISO-Principle. For negative moods, songs begin by validating the current feeling, transition gradually, and finish with a more positive emotional direction.',
    );
  }

  Future<void> _showPrivacyDialog(BuildContext context) {
    return _showInformationDialog(
      context,
      title: 'Data and privacy',
      icon: Icons.shield_outlined,
      text:
          'AURALIA uses your account information, selected moods, saved playlists, and favourites to provide your profile, analytics, and personalized recommendations. Spotify authorization is handled by Spotify and your Spotify password is not stored by AURALIA.',
    );
  }

  Future<void> _showInformationDialog(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String text,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(icon, color: const Color(0xFF5A2C62)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF38143E),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.45,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Got it',
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
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? 'A' : name.substring(0, 1).toUpperCase();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A0736), Color(0xFF64226D), Color(0xFF9B5A91)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Stack(
        children: [
          const FloatingBubbles(count: 14, opacity: 0.15),
          Row(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Text(
                        'AURALIA listener',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Edit profile',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF38143E),
        ),
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.length < 2) {
              return 'Enter at least 2 characters';
            }
            if (name.length > 40) {
              return 'Name must be 40 characters or less';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A2C62),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirmation = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.of(context).pop(_passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Change password',
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF38143E),
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _hidePassword,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final password = value ?? '';
                if (password.length < 8) {
                  return 'Use at least 8 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmController,
              obscureText: _hideConfirmation,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  tooltip: _hideConfirmation
                      ? 'Show password'
                      : 'Hide password',
                  onPressed: () => setState(
                    () => _hideConfirmation = !_hideConfirmation,
                  ),
                  icon: Icon(
                    _hideConfirmation
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A2C62),
          ),
          child: const Text('Update password'),
        ),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _controller = TextEditingController();

  bool get _canDelete => _controller.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB3404A),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delete account?',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF38143E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'This will permanently remove your AURALIA account, mood history, saved playlists, tracks, and favourites.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Type DELETE to confirm.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8C3343),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Confirmation',
                  prefixIcon: Icon(Icons.delete_outline_rounded),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _canDelete
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF8C3343),
                    ),
                    child: const Text('Delete account'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF38143E),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                const Divider(height: 1, indent: 58, endIndent: 16),
            ],
          );
        }),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _RowLayout(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: null,
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.connected,
    this.actionLabel,
    this.onAction,
    this.isBusy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool connected;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return _RowLayout(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: actionLabel == null
          ? Icon(
              connected
                  ? Icons.check_circle_rounded
                  : Icons.info_outline_rounded,
              color: connected
                  ? const Color(0xFF348557)
                  : Colors.black38,
            )
          : TextButton(
              onPressed: isBusy ? null : onAction,
              child: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      actionLabel!,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5A2C62),
                      ),
                    ),
            ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _RowLayout(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.black38,
        ),
      ),
    );
  }
}

class _DangerActionRow extends StatelessWidget {
  const _DangerActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _RowLayout(
        icon: icon,
        title: title,
        subtitle: subtitle,
        iconColor: const Color(0xFF8C3343),
        iconBackgroundColor: const Color(0xFFFFE7EA),
        titleColor: const Color(0xFF8C3343),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFB86A74),
        ),
      ),
    );
  }
}

class _RowLayout extends StatelessWidget {
  const _RowLayout({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.iconColor = const Color(0xFF5A2C62),
    this.iconBackgroundColor = const Color(0xFFEDE4EE),
    this.titleColor = const Color(0xFF38143E),
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color iconColor;
  final Color iconBackgroundColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconBackgroundColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
