import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class UserProfile {
  final String id;
  final String name;
  final DateTime registeredAt;
  final DateTime lastOnline;
  final String email;
  final String info;

  UserProfile({
    required this.id,
    required this.name,
    required this.registeredAt,
    required this.lastOnline,
    required this.email,
    required this.info,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      registeredAt: DateTime.parse(json['registered_at'] ?? DateTime.now().toIso8601String()),
      lastOnline: DateTime.parse(json['last_online'] ?? DateTime.now().toIso8601String()),
      email: json['email'] ?? '',
      info: json['info'] ?? '',
    );
  }

  bool get isOnline {
    final now = DateTime.now();
    final diff = now.difference(lastOnline);
    return diff.inMinutes < 15; // Consider online if active within 15 minutes
  }
}

class UserProfilesResponse {
  final List<UserProfile> profiles;
  final int total;
  final int limit;
  final int offset;
  final bool hasMore;

  UserProfilesResponse({
    required this.profiles,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasMore,
  });

  factory UserProfilesResponse.fromJson(Map<String, dynamic> json) {
    final profilesList = json['profiles'] as List<dynamic>? ?? [];
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};

    return UserProfilesResponse(
      profiles: profilesList.map((profile) => UserProfile.fromJson(profile)).toList(),
      total: pagination['total'] ?? 0,
      limit: pagination['limit'] ?? 20,
      offset: pagination['offset'] ?? 0,
      hasMore: pagination['has_more'] ?? false,
    );
  }
}

class UserProfileService {
  static const String _baseUrl = 'http://localhost:8888/api/v1';
  
  static String get _apiToken {
    return dotenv.env['API_TOKEN'] ?? '';
  }

  static Future<UserProfilesResponse> getUserProfiles({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/users/profiles')
          .replace(queryParameters: {
        'token': _apiToken,
        'limit': limit.toString(),
        'offset': offset.toString(),
      });

      print('Fetching user profiles from: $url');

      final response = await http.get(url);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return UserProfilesResponse.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to load user profiles: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user profiles: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<UserProfile> getUserProfile(String userId) async {
    try {
      final url = Uri.parse('$_baseUrl/users/profile')
          .replace(queryParameters: {
        'id': userId,
        'token': _apiToken,
      });

      print('Fetching user profile from: $url');

      final response = await http.get(url);

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
        throw Exception('Failed to load user profile: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user profile: $e');
      throw Exception('Network error: $e');
    }
  }
} 