import 'package:flutter/foundation.dart';
import '../services/users_service.dart';

class FollowedState extends ChangeNotifier {
  // Data
  List<UserProfile> _followedUsers = [];
  
  // UI state
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;
  
  // Track if initial load is complete
  bool _hasLoaded = false;
  
  // Getters
  List<UserProfile> get followedUsers => List.unmodifiable(_followedUsers);
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  
  /// Load followed users once on app startup
  Future<void> loadFollowedUsers({required String userId, bool silent = false}) async {
    // If already loaded and not forcing refresh, return immediately
    if (_hasLoaded && !silent) {
      debugPrint('👥 [FOLLOWED] Using cached followed users (${_followedUsers.length} items)');
      return;
    }
    
    try {
      if (!silent) {
        _isLoading = true;
        notifyListeners();
      } else {
        _isRefreshing = true;
      }
      
      _error = null;
      
      final response = await UsersService.getFollowedUsers(userId);
      _followedUsers = response.users;
      _hasLoaded = true;
      
      debugPrint('👥 [FOLLOWED] Loaded followed users: ${_followedUsers.length} items');
    } catch (e) {
      _error = 'Failed to load followed users: $e';
      debugPrint('❌ [FOLLOWED] Error loading followed users: $e');
      // Don't rethrow - just set empty list
      _followedUsers = [];
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }
  
  /// Refresh followed users in background (silent update)
  Future<void> refreshFollowedUsersInBackground(String userId) async {
    if (!_hasLoaded) {
      // If not loaded yet, do a normal load
      await loadFollowedUsers(userId: userId);
      return;
    }
    
    debugPrint('🔄 [FOLLOWED] Refreshing followed users in background...');
    await loadFollowedUsers(userId: userId, silent: true);
  }
  
  /// Follow a user (optimistic update with background sync)
  Future<bool> followUser({
    required String userId,
    required UserProfile targetUser,
  }) async {
    // Optimistically add to local list
    if (!_followedUsers.any((u) => u.id == targetUser.id)) {
      _followedUsers = [..._followedUsers, targetUser];
      notifyListeners();
    }
    
    // Sync to server in background
    try {
      await UsersService.followUser(userId, targetUser.id);
      debugPrint('✅ [FOLLOWED] Followed user: ${targetUser.username}');
      return true;
    } catch (e) {
      // Rollback on error
      _followedUsers = _followedUsers.where((u) => u.id != targetUser.id).toList();
      notifyListeners();
      debugPrint('❌ [FOLLOWED] Failed to follow user: $e');
      return false;
    }
  }
  
  /// Unfollow a user (optimistic update with background sync)
  Future<bool> unfollowUser({
    required String userId,
    required String targetUserId,
  }) async {
    // Find and save the user in case we need to rollback
    final removedIndex = _followedUsers.indexWhere((u) => u.id == targetUserId);
    if (removedIndex == -1) {
      debugPrint('❌ [FOLLOWED] User not found in followed list: $targetUserId');
      return false;
    }
    
    final removedUser = _followedUsers[removedIndex];
    
    // Optimistically remove from local list
    _followedUsers = List.from(_followedUsers)..removeAt(removedIndex);
    notifyListeners();
    
    // Sync to server in background
    try {
      await UsersService.unfollowUser(userId, targetUserId);
      debugPrint('✅ [FOLLOWED] Unfollowed user: ${removedUser.username}');
      return true;
    } catch (e) {
      // Rollback on error - restore at original position
      _followedUsers = List.from(_followedUsers)..insert(removedIndex, removedUser);
      notifyListeners();
      debugPrint('❌ [FOLLOWED] Failed to unfollow user: $e');
      return false;
    }
  }
  
  /// Clear all data (e.g., on logout)
  void clear() {
    _followedUsers = [];
    _hasLoaded = false;
    _error = null;
    _isLoading = false;
    _isRefreshing = false;
    notifyListeners();
    debugPrint('👥 [FOLLOWED] Cleared followed users data');
  }
}
