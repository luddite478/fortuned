import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/user_profile_widget.dart';
import '../utils/app_colors.dart';
import '../services/users_service.dart';
import '../services/auth_service.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final bool isOnline;
  final Function(bool isFollowing)? onFollowStatusChanged;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.isOnline = false,
    this.onFollowStatusChanged,
  }) : super(key: key);

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _isFollowing = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) return;
      
      // Get followed users to check if we're already following this user
      final response = await UsersService.getFollowedUsers(currentUserId);
      final isFollowing = response.users.any((user) => user.id == widget.userId);
      
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }
    } catch (e) {
      print('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to follow users')),
        );
        return;
      }

      if (currentUserId == widget.userId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot follow yourself')),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      if (_isFollowing) {
        await UsersService.unfollowUser(currentUserId, widget.userId);
      } else {
        await UsersService.followUser(currentUserId, widget.userId);
      }

      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          _isLoading = false;
        });
        
        // Notify parent about follow status change
        widget.onFollowStatusChanged?.call(_isFollowing);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.id;
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: AppColors.menuPageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.menuEntryBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: AppColors.menuText,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.userName,
          style: const TextStyle(
            color: AppColors.menuText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          // Follow button (only show if not own profile and user is logged in)
          if (!isOwnProfile && currentUserId != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.menuText,
                      ),
                    )
                  : TextButton(
                      onPressed: _toggleFollow,
                      style: TextButton.styleFrom(
                        backgroundColor: _isFollowing 
                            ? AppColors.menuLightText.withOpacity(0.2)
                            : AppColors.menuText,
                        foregroundColor: _isFollowing 
                            ? AppColors.menuText
                            : AppColors.menuPageBackground,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                          side: _isFollowing 
                              ? BorderSide(color: AppColors.menuText, width: 1)
                              : BorderSide.none,
                        ),
                      ),
                      child: Text(
                        _isFollowing ? 'Following' : 'Follow',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
            ),
          
          // Online indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.isOnline ? AppColors.menuOnlineIndicator : AppColors.menuLightText,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.menuBorder,
          ),
        ),
      ),
      body: SafeArea(
        child: UserProfileWidget(
          userId: widget.userId,
          userName: widget.userName,
          isOnline: widget.isOnline,
        ),
      ),
    );
  }
} 