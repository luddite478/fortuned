import 'package:flutter/material.dart';
import '../widgets/user_profile_widget.dart';
import '../utils/app_colors.dart';

class UserProfileScreen extends StatelessWidget {
  final String userId;
  final String userName;
  final bool isOnline;

  const UserProfileScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.isOnline = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
          userName,
          style: const TextStyle(
            color: AppColors.menuText,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
              Container(
            margin: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? AppColors.menuOnlineIndicator : AppColors.menuLightText,
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
          userId: userId,
          userName: userName,
          isOnline: isOnline,
        ),
      ),
    );
  }
} 