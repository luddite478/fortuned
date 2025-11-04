import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/users_service.dart';
import '../models/playlist_item.dart';

class UserState extends ChangeNotifier {
  static const String _userKey = 'device_user';

  UserProfile? _currentUser;
  bool _isLoading = true;

  UserProfile? get currentUser => _currentUser;
  String? get currentUserId => _currentUser?.id;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _currentUser != null;

  UserState() {
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    _isLoading = true;
    notifyListeners();

    // Check for a flag to clear storage on startup
    const shouldClear = bool.fromEnvironment('CLEAR_STORAGE');
    if (shouldClear) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
      debugPrint('🗑️ [USER] Storage cleared on startup.');
    }

    const devUserId = String.fromEnvironment('DEV_USER_ID');
    UserProfile? localUser;

    if (devUserId.isNotEmpty) {
      // Dev mode: Use the hardcoded developer user ID
      localUser = _createAnonymousUser(id: devUserId, name: 'Dev User');
      debugPrint('🔧 [USER] Using developer user ID: ${localUser.id}');
    } else {
      // Production mode: Load from storage or create a new random user
      try {
        final prefs = await SharedPreferences.getInstance();
        final userJson = prefs.getString(_userKey);

        if (userJson != null) {
          final userData = json.decode(userJson);
          final isHex24 = RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(userData['id'] ?? '');
          if (isHex24) {
            localUser = UserProfile.fromJson(userData);
            debugPrint('✅ [USER] User loaded from storage: ${localUser.id}');
          }
        }
      } catch(e) {
        debugPrint('❌ [USER] Could not load user from storage: $e');
      }
    }
    
    if (localUser == null) {
      localUser = _createAnonymousUser();
      debugPrint('✨ [USER] Created new anonymous user: ${localUser.id}');
      await _saveUser(localUser);
    }

    _currentUser = await UsersService.getOrCreateUser(localUser);
    debugPrint('✅ [USER] User synchronized with backend: ${_currentUser!.id}');
    
    // Only save if it's not a dev user, to avoid overwriting a real user's data on another device
    if (devUserId.isEmpty) {
      await _saveUser(_currentUser!);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshCurrentUserFromServer() async {
    try {
      if (_currentUser == null) return;
      final fetched = await UsersService.getUser(_currentUser!.id);
      _currentUser = fetched;
      await _saveUser(_currentUser!);
      notifyListeners();
    } catch (e) {
      // Ignore network errors silently for now
    }
  }

  Future<bool> updateUsername(String newUsername) async {
    try {
      if (_currentUser == null) return false;
      
      debugPrint('🔧 [USER] Updating username to: $newUsername');
      
      // Call API to update username
      final updatedUser = await UsersService.updateUsername(_currentUser!.id, newUsername);
      
      // Update local state
      _currentUser = updatedUser;
      
      // Save to local storage
      await _saveUser(_currentUser!);
      
      // Notify listeners
      notifyListeners();
      
      debugPrint('✅ [USER] Username updated successfully: $newUsername');
      return true;
    } catch (e) {
      debugPrint('❌ [USER] Failed to update username: $e');
      return false;
    }
  }

  UserProfile _createAnonymousUser({String? id, String? name}) {
    final newId = id ?? _generateHexId(24);
    
    return UserProfile(
      id: newId,
      username: name ?? '',  // Empty string for new anonymous users
      name: name ?? '',  // Empty string for new anonymous users
      email: '$newId@anonymous.com',
      createdAt: DateTime.now(),
      lastLogin: DateTime.now(),
      lastOnline: DateTime.now(),
      isActive: true,
      emailVerified: false,
      profile: UserProfileInfo(bio: '', location: ''),
      stats: UserStats(totalPlays: 0),
      preferences: UserPreferences(theme: 'dark'),
      threads: const [],
      pendingInvitesToThreads: const [],
      playlist: const [],
    );
  }

  Future<void> _saveUser(UserProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(user.toJson()));
  }

  String _generateHexId(int length) {
    final random = Random();
    const chars = 'abcdef0123456789';
    return String.fromCharCodes(Iterable.generate(
        length, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }
}
