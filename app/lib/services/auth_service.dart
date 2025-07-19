import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'users_service.dart';

class AuthService extends ChangeNotifier {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _loginTimeKey = 'login_time';
  
  bool _isAuthenticated = false;
  UserProfile? _currentUser;
  String? _token;
  bool _isLoading = false;

  bool get isAuthenticated => _isAuthenticated;
  UserProfile? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;

  AuthService() {
    print('🐛 [AUTH] AuthService constructor called');
    _loadAuthState();
  }

  Future<void> _loadAuthState() async {
    print('🐛 [AUTH] Starting _loadAuthState()');
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      final userJson = prefs.getString(_userKey);
      final loginTime = prefs.getInt(_loginTimeKey);
      
      print('🐛 [AUTH] Loaded from storage:');
      print('🐛   - token: ${_token != null ? 'EXISTS' : 'null'}');
      print('🐛   - userJson: ${userJson != null ? 'EXISTS' : 'null'}');
      print('🐛   - loginTime: $loginTime');

      if (_token != null && userJson != null && loginTime != null) {
        // Check if login is still valid (7 days)
        final loginDate = DateTime.fromMillisecondsSinceEpoch(loginTime);
        final daysSinceLogin = DateTime.now().difference(loginDate).inDays;
        
        print('🐛 [AUTH] Login age: $daysSinceLogin days');
        
        if (daysSinceLogin < 7) {
          _currentUser = UserProfile.fromJson(json.decode(userJson));
          _isAuthenticated = true;
          print('🐛 [AUTH] ✅ User authenticated from storage: ${_currentUser?.id}');
        } else {
          // Login expired, clear stored data
          print('🐛 [AUTH] ❌ Login expired, clearing stored data');
          await clearAuthState();
        }
      } else {
        print('🐛 [AUTH] ❌ No valid stored auth data found');
      }
    } catch (e) {
      print('🐛 [AUTH] ❌ Error loading auth state: $e');
      await clearAuthState();
    }

    _isLoading = false;
    print('🐛 [AUTH] _loadAuthState() completed:');
    print('🐛   - _isLoading: $_isLoading');
    print('🐛   - _isAuthenticated: $_isAuthenticated');
    print('🐛   - _currentUser: ${_currentUser?.id ?? 'null'}');
    notifyListeners();
  }

  Future<AuthResult> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await UsersService.login(email, password);
      
      if (response.success && response.userId != null) {
        // Create UserProfile from AuthResponse data
        _currentUser = UserProfile(
          id: response.userId!,
          username: response.username ?? '',
          name: response.name ?? '',
          email: response.email ?? '',
          createdAt: DateTime.now(),
          lastLogin: DateTime.now(),
          lastOnline: DateTime.now(),
          isActive: true,
          emailVerified: false,
          profile: UserProfileInfo(bio: '', location: ''),
          stats: UserStats(totalPlays: 0),
          preferences: UserPreferences(theme: 'dark'),
        );
        
        _isAuthenticated = true;
        _token = dotenv.env['API_TOKEN'] ?? 'asdfasdasduiu546';
        
        // Save to local storage
        await _saveAuthState();
        
        _isLoading = false;
        notifyListeners();
        return AuthResult(success: true, message: response.message ?? 'Login successful');
      } else {
        _isLoading = false;
        notifyListeners();
        return AuthResult(success: false, message: response.message ?? 'Login failed');
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return AuthResult(success: false, message: 'Login error: $e');
    }
  }

  Future<AuthResult> register(String username, String name, String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await UsersService.register(username, name, email, password);
      
      if (response.success && response.userId != null) {
        // Create UserProfile from AuthResponse data
        _currentUser = UserProfile(
          id: response.userId!,
          username: response.username ?? username,
          name: response.name ?? name,
          email: response.email ?? email,
          createdAt: DateTime.now(),
          lastLogin: DateTime.now(),
          lastOnline: DateTime.now(),
          isActive: true,
          emailVerified: false,
          profile: UserProfileInfo(bio: '', location: ''),
          stats: UserStats(totalPlays: 0),
          preferences: UserPreferences(theme: 'dark'),
        );
        
        _isAuthenticated = true;
        _token = dotenv.env['API_TOKEN'] ?? 'asdfasdasduiu546';
        
        await _saveAuthState();
        
        _isLoading = false;
        notifyListeners();
        return AuthResult(success: true, message: response.message ?? 'Registration successful');
      } else {
        _isLoading = false;
        notifyListeners();
        return AuthResult(success: false, message: response.message ?? 'Registration failed');
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return AuthResult(success: false, message: 'Registration error: $e');
    }
  }

  Future<void> _saveAuthState() async {
    if (_currentUser != null && _token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, _token!);
      await prefs.setString(_userKey, json.encode(_currentUser!.toJson()));
      await prefs.setInt(_loginTimeKey, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<void> logout() async {
    await clearAuthState();
    _isAuthenticated = false;
    _currentUser = null;
    _token = null;
    notifyListeners();
  }

  Future<void> clearAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_loginTimeKey);
  }

  Future<void> forceLogin() async {
    await logout();
  }
}

class AuthResult {
  final bool success;
  final String message;

  AuthResult({required this.success, required this.message});
} 