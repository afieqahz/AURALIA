import '../models/app_user.dart';

abstract class AuthService {
  AppUser? get currentUser;

  Future<bool> restoreSession();

  Future<AppUser> signIn({required String email, required String password});

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String name,
  });

  Future<void> resetPassword({required String email});

  Future<void> completePasswordReset({
    required String accessToken,
    required String newPassword,
  });

  Future<AppUser> updateProfile({required String name});

  Future<void> changePassword({required String newPassword});

  Future<void> deleteAccount();

  Future<void> signOut();
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthEmailConfirmationRequired extends AuthFlowException {
  const AuthEmailConfirmationRequired()
    : super(
        'Account created. Check your email to confirm your account, then log in.',
      );
}

class LocalAuthService implements AuthService {
  AppUser? _currentUser;

  @override
  AppUser? get currentUser => _currentUser;

  @override
  Future<bool> restoreSession() async {
    return _currentUser != null;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _currentUser = AppUser(
      id: 'local-user',
      email: email,
      name: _nameFromEmail(email),
    );
    return _currentUser!;
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _currentUser = AppUser(id: 'local-user', email: email, name: name);
    return _currentUser!;
  }

  @override
  Future<void> resetPassword({required String email}) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<void> completePasswordReset({
    required String accessToken,
    required String newPassword,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<AppUser> updateProfile({required String name}) async {
    final user = _currentUser;
    if (user == null) {
      throw const AuthFlowException('You must be logged in to edit your profile.');
    }
    _currentUser = AppUser(id: user.id, email: user.email, name: name);
    return _currentUser!;
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    if (_currentUser == null) {
      throw const AuthFlowException(
        'You must be logged in to change your password.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  @override
  Future<void> deleteAccount() async {
    if (_currentUser == null) {
      throw const AuthFlowException(
        'You must be logged in to delete your account.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _currentUser = null;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
  }

  String _nameFromEmail(String email) {
    final prefix = email.split('@').first.trim();
    if (prefix.isEmpty) {
      return 'Afiqah';
    }
    return prefix[0].toUpperCase() + prefix.substring(1);
  }
}
