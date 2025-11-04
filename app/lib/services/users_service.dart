import 'dart:convert';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'http_client.dart';
import 'ws_client.dart';
import '../models/playlist_item.dart';

class UserProfile {
  final String id;
  final String username;
  final String name;
  final String email;
  final DateTime createdAt;
  final DateTime lastLogin;
  final DateTime lastOnline;
  final bool isActive;
  final bool emailVerified;
  final UserProfileInfo profile;
  final UserStats stats;

  final UserPreferences preferences;
  final List<String> threads;
  final List<String> pendingInvitesToThreads;
  final List<PlaylistItem> playlist;

  UserProfile({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    required this.createdAt,
    required this.lastLogin,
    required this.lastOnline,
    required this.isActive,
    required this.emailVerified,
    required this.profile,
    required this.stats,

    required this.preferences,
    this.threads = const [],
    this.pendingInvitesToThreads = const [],
    this.playlist = const [],
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      lastLogin: DateTime.parse(json['last_login'] ?? DateTime.now().toIso8601String()),
      lastOnline: DateTime.parse(json['last_online'] ?? DateTime.now().toIso8601String()),
      isActive: json['is_active'] ?? true,
      emailVerified: json['email_verified'] ?? false,
      profile: UserProfileInfo.fromJson(json['profile'] ?? {}),
      stats: UserStats.fromJson(json['stats'] ?? {}),

      preferences: UserPreferences.fromJson(json['preferences'] ?? {}),
      threads: (json['threads'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      pendingInvitesToThreads: (json['pending_invites_to_threads'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      playlist: (json['playlist'] as List<dynamic>? ?? []).map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'email': email,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin.toIso8601String(),
      'last_online': lastOnline.toIso8601String(),
      'is_active': isActive,
      'email_verified': emailVerified,
      'profile': {
        'bio': profile.bio,
        'location': profile.location,
      },
              'stats': {
          'total_plays': stats.totalPlays,
        },

              'preferences': {
          'theme': preferences.theme,
        },
      'threads': threads,
      'pending_invites_to_threads': pendingInvitesToThreads,
    };
  }

  bool get isOnline {
    final now = DateTime.now();
    final diff = now.difference(lastOnline);
    return diff.inMinutes < 15; // Consider online if active within 15 minutes
  }

  // Legacy properties for backward compatibility
  String get info => profile.bio;
  String get bio => profile.bio;
  DateTime get registeredAt => createdAt;
  DateTime get joinedDate => createdAt;
  String get avatar => '👤';
  bool get isWorking => false;
  String get currentProject => '';
  int get totalSeries => 0;
  int get totalTracks => 0;
}

class UserProfileInfo {
  final String bio;
  final String location;

  UserProfileInfo({
    required this.bio,
    required this.location,
  });

  factory UserProfileInfo.fromJson(Map<String, dynamic> json) {
    return UserProfileInfo(
      bio: json['bio'] ?? '',
      location: json['location'] ?? '',
    );
  }
}

class UserStats {
  final int totalPlays;

  UserStats({
    required this.totalPlays,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalPlays: json['total_plays'] ?? 0,
    );
  }
}

class UserPreferences {
  final String theme;

  UserPreferences({
    required this.theme,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      theme: json['theme'] ?? 'dark',
    );
  }
}

class UsersResponse {
  final List<UserProfile> users;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  UsersResponse({
    required this.users,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory UsersResponse.fromJson(Map<String, dynamic> json) {
    final usersList = json['users'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return UsersResponse(
      users: usersList.map((user) => UserProfile.fromJson(user)).toList(),
      total: pagination['total'] ?? 0,
      limit: pagination['limit'] ?? 20,
      offset: pagination['offset'] ?? 0,
      hasMore: pagination['has_more'] ?? false,
    );
  }

  // Legacy getter for backward compatibility
  List<UserProfile> get profiles => users;
}

class LoginRequest {
  final String email;
  final String password;

  LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
    };
  }
}

class RegisterRequest {
  final String username;
  final String name;
  final String email;
  final String password;

  RegisterRequest({
    required this.username,
    required this.name,
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'name': name,
      'email': email,
      'password': password,
    };
  }
}

class AuthResponse {
  final bool success;
  final String? userId;
  final String? username;
  final String? name;
  final String? email;
  final String? message;

  AuthResponse({
    required this.success,
    this.userId,
    this.username,
    this.name,
    this.email,
    this.message,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      success: json['success'] ?? false,
      userId: json['user_id'],
      username: json['username'],
      name: json['name'],
      email: json['email'],
      message: json['message'] ?? json['detail'],
    );
  }
}

class UsersService {
  static String get _baseUrl {
    final serverIp = dotenv.env['SERVER_HOST'] ?? '';
    final apiPort = dotenv.env['HTTPS_API_PORT'] ?? '443';
    final protocol = 'https';
    final port = apiPort == '443' ? '' : ':$apiPort';
    return '$protocol://$serverIp$port/api/v1';
  }
  
  static String get _apiToken {
    final token = dotenv.env['API_TOKEN'] ?? '';
    print('API_TOKEN from env: "$token"');
    print('All env vars: ${dotenv.env.keys.toList()}');
    
    return token;
  }

  // WebSocket client for real-time online users functionality
  final WebSocketClient _wsClient;
  
  // Stream controller for online users
  final _onlineUsersController = StreamController<List<String>>.broadcast();
  
  // Getter for online users stream
  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;
  Stream<bool> get connectionStream => _wsClient.connectionStream;
  Stream<String> get errorStream => _wsClient.errorStream;
  bool get isConnected => _wsClient.isConnected;
  String? get clientId => _wsClient.clientId;

  UsersService({required WebSocketClient wsClient}) : _wsClient = wsClient {
    // Register handler for online users messages
    _wsClient.registerMessageHandler('online_users', _handleOnlineUsers);
  }

  void _handleOnlineUsers(Map<String, dynamic> message) {
    if (!_onlineUsersController.isClosed) {
      final users = List<String>.from(message['users'] ?? []);
      _onlineUsersController.add(users);
    }
  }

  // Request list of online users
  Future<bool> requestOnlineUsers() async {
    final request = {
      'type': 'list_users',
    };
    return await _wsClient.sendMessage(request);
  }

  // Dispose method to clean up resources
  void dispose() {
    // Unregister message handlers
    _wsClient.unregisterAllHandlers('online_users');
    
    if (!_onlineUsersController.isClosed) {
      _onlineUsersController.close();
    }
  }

  static Future<AuthResponse> login(String email, String password) async {
    try {
      final loginRequest = LoginRequest(email: email, password: password);
      
      print('Attempting login to: /auth/login');

      final response = await ApiHttpClient.post('/auth/login', 
        body: loginRequest.toJson(),
      );

      print('Login response status: ${response.statusCode}');
      print('Login response body: ${response.body}');

      final jsonData = json.decode(response.body);
      return AuthResponse.fromJson(jsonData);
    } catch (e) {
      print('Error during login: $e');
      return AuthResponse(
        success: false,
        message: 'Login failed: $e',
      );
    }
  }

  static Future<AuthResponse> register(String username, String name, String email, String password) async {
    try {
      final registerRequest = RegisterRequest(
        username: username,
        name: name,
        email: email,
        password: password,
      );

      print('Attempting registration to: /auth/register');

      final response = await ApiHttpClient.post('/auth/register', 
        body: registerRequest.toJson(),
      );

      print('Register response status: ${response.statusCode}');
      print('Register response body: ${response.body}');

      final jsonData = json.decode(response.body);
      return AuthResponse.fromJson(jsonData);
    } catch (e) {
      print('Error during registration: $e');
      return AuthResponse(
        success: false,
        message: 'Registration failed: $e',
      );
    }
  }

  static Future<UsersResponse> getUsers({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Try to reload dotenv if token is empty
      if (dotenv.env['API_TOKEN']?.isEmpty ?? true) {
        print('API_TOKEN is empty, reloading dotenv...');
        await dotenv.load(fileName: ".env");
      }
      
      final queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      print('Query params: $queryParams');
      
      print('Fetching users from: /users/list');

      final response = await ApiHttpClient.get('/users/list', queryParams: queryParams);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return UsersResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching users: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<UserProfile> getUser(String userId) async {
    try {
      final queryParams = {
        'id': userId,
      };

      print('Fetching user from: /users/user');

      final response = await ApiHttpClient.get('/users/user', queryParams: queryParams);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return UserProfile.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else if (response.statusCode == 404) {
        throw Exception('User not found');
      } else {
        throw Exception('Failed to load user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> followUser(String userId, String targetUserId) async {
    try {
      final body = {
        'user_id': userId,
        'target_user_id': targetUserId,
      };

      print('Following user: $targetUserId');

      final response = await ApiHttpClient.post('/users/follow', body: body);

      print('Follow response status: ${response.statusCode}');
      print('Follow response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return jsonData;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to follow user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error following user: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<Map<String, dynamic>> unfollowUser(String userId, String targetUserId) async {
    try {
      final body = {
        'user_id': userId,
        'target_user_id': targetUserId,
      };

      print('Unfollowing user: $targetUserId');

      final response = await ApiHttpClient.post('/users/unfollow', body: body);

      print('Unfollow response status: ${response.statusCode}');
      print('Unfollow response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return jsonData;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to unfollow user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error unfollowing user: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<UsersResponse> searchUsers(String query, {int limit = 20}) async {
    try {
      final queryParams = {
        'query': query,
        'limit': limit.toString(),
      };

      print('Searching users with query: $query');

      final response = await ApiHttpClient.get('/users/search', queryParams: queryParams);

      print('Search response status: ${response.statusCode}');
      print('Search response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        // Convert to UsersResponse format
        return UsersResponse(
          users: (jsonData['users'] as List<dynamic>)
              .map((user) => UserProfile.fromJson(user))
              .toList(),
          total: jsonData['count'] ?? 0,
          limit: limit,
          offset: 0,
          hasMore: false,
        );
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to search users: ${response.statusCode}');
      }
    } catch (e) {
      print('Error searching users: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<UsersResponse> getFollowedUsers(String userId) async {
    try {
      final queryParams = {
        'user_id': userId,
      };

      print('Getting followed users for: $userId');

      final response = await ApiHttpClient.get('/users/following', queryParams: queryParams);

      print('Following response status: ${response.statusCode}');
      print('Following response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        // Convert to UsersResponse format
        return UsersResponse(
          users: (jsonData['users'] as List<dynamic>)
              .map((user) => UserProfile.fromJson(user))
              .toList(),
          total: jsonData['count'] ?? 0,
          limit: 20,
          offset: 0,
          hasMore: false,
        );
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to get followed users: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting followed users: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<UserProfile> getOrCreateUser(UserProfile user) async {
    try {
      print('Attempting to get or create user: ${user.id}');

      final response = await ApiHttpClient.post('/users/session',
        body: user.toJson(),
      );

      print('Get-or-create response status: ${response.statusCode}');
      print('Get-or-create response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final jsonData = json.decode(response.body);
        return UserProfile.fromJson(jsonData);
      } else {
        throw Exception('Failed to get or create user: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during get-or-create user: $e');
      // In case of network error, just return the local user profile
      // The app can retry later.
      return user;
    }
  }

  static Future<UserProfile> updateUsername(String userId, String newUsername) async {
    try {
      print('Updating username for user: $userId to: $newUsername');

      final response = await ApiHttpClient.put('/users/$userId/username',
        body: {'username': newUsername},
      );

      print('Update username response status: ${response.statusCode}');
      print('Update username response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return UserProfile.fromJson(jsonData);
      } else if (response.statusCode == 400) {
        final jsonData = json.decode(response.body);
        throw Exception(jsonData['detail'] ?? 'Invalid username');
      } else {
        throw Exception('Failed to update username: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating username: $e');
      rethrow;
    }
  }

  // Legacy methods for backward compatibility
  static Future<UsersResponse> getUserProfiles({int limit = 20, int offset = 0}) {
    return getUsers(limit: limit, offset: offset);
  }

  static Future<UserProfile> getUserProfile(String userId) {
    return getUser(userId);
  }
}

// Data models - Note: Thread, ProjectCheckpoint, etc. are imported from threads_state.dart
// Legacy data models below are kept for backward compatibility with existing UI components

// class SoundTrack {
//   final String id;
//   final String name;
//   final String url;
//   final Duration duration;

//   SoundTrack({
//     required this.id,
//     required this.name,
//     required this.url,
//     required this.duration,
//   });

//   factory SoundTrack.fromJson(Map<String, dynamic> json) {
//     return SoundTrack(
//       id: json['id'] ?? '',
//       name: json['name'] ?? '',
//       url: json['url'] ?? '',
//       duration: Duration(seconds: json['duration_seconds'] ?? 0),
//     );
//   }
// }

// class AudioRender {
//   final String id;
//   final String url;
//   final String createdAt;
//   final String version;
//   final String quality;

//   AudioRender({
//     required this.id,
//     required this.url,
//     required this.createdAt,
//     required this.version,
//     required this.quality,
//   });

//   factory AudioRender.fromJson(Map<String, dynamic> json) {
//     return AudioRender(
//       id: json['id'] ?? '',
//       url: json['url'] ?? '',
//       createdAt: json['created_at'] ?? '',
//       version: json['version'] ?? '',
//       quality: json['quality'] ?? '',
//     );
//   }
// }

// class AudioSource {
//   final List<GridData> gridStacks;
//   final List<SampleData> samples;

//   AudioSource({
//     required this.gridStacks,
//     required this.samples,
//   });

//   factory AudioSource.fromJson(Map<String, dynamic> json) {
//     final sections = json['sections'] as List<dynamic>? ?? [];
//     final samplesList = json['samples'] as List<dynamic>? ?? [];
    
//     return AudioSource(
//       gridStacks: sections.map((grid) => GridData.fromJson(grid)).toList(),
//       samples: samplesList.map((sample) => SampleData.fromJson(sample)).toList(),
//     );
//   }
// }

// class GridData {
//   final List<List<GridCell>> layers;
//   final GridMetadata metadata;

//   GridData({
//     required this.layers,
//     required this.metadata,
//   });

//   factory GridData.fromJson(Map<String, dynamic> json) {
//     final layersList = json['layers'] as List<dynamic>? ?? [];
    
//     return GridData(
//       layers: layersList.map((layer) {
//         final layerCells = layer as List<dynamic>;
//         return layerCells.map((cell) => GridCell.fromJson(cell)).toList();
//       }).toList(),
//       metadata: GridMetadata.fromJson(json['metadata'] ?? {}),
//     );
//   }
// }

// class GridMetadata {
//   final String user;
//   final String createdAt;
//   final int bpm;
//   final String key;
//   final String timeSignature;

//   GridMetadata({
//     required this.user,
//     required this.createdAt,
//     required this.bpm,
//     required this.key,
//     required this.timeSignature,
//   });

//   factory GridMetadata.fromJson(Map<String, dynamic> json) {
//     return GridMetadata(
//       user: json['user'] ?? '',
//       createdAt: json['created_at'] ?? '',
//       bpm: json['bpm'] ?? 120,
//       key: json['key'] ?? 'C Major',
//       timeSignature: json['time_signature'] ?? '4/4',
//     );
//   }
// }

// class GridCell {
//   final String? sampleId;
//   final String? sampleName;

//   GridCell({
//     this.sampleId,
//     this.sampleName,
//   });

//   factory GridCell.fromJson(Map<String, dynamic> json) {
//     return GridCell(
//       sampleId: json['sample_id'],
//       sampleName: json['sample_name'],
//     );
//   }

//   bool get isEmpty => sampleId == null || sampleId!.isEmpty;
// }

// class SampleData {
//   final String id;
//   final String name;
//   final String url;
//   final bool isPublic;

//   SampleData({
//     required this.id,
//     required this.name,
//     required this.url,
//     required this.isPublic,
//   });

//   factory SampleData.fromJson(Map<String, dynamic> json) {
//     return SampleData(
//       id: json['id'] ?? '',
//       name: json['name'] ?? '',
//       url: json['url'] ?? '',
//       isPublic: json['is_public'] ?? false,
//     );
//   }
// } 