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
  final String avatar;
  final String bio;
  final bool isWorking;
  final String currentProject;
  final int totalSeries;
  final int totalTracks;
  final DateTime joinedDate;

  UserProfile({
    required this.id,
    required this.name,
    required this.registeredAt,
    required this.lastOnline,
    required this.email,
    required this.info,
    this.avatar = '👤',
    String? bio,
    this.isWorking = false,
    this.currentProject = '',
    this.totalSeries = 0,
    this.totalTracks = 0,
    DateTime? joinedDate,
  }) : bio = bio ?? info,
       joinedDate = joinedDate ?? registeredAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      registeredAt: DateTime.parse(json['registered_at'] ?? DateTime.now().toIso8601String()),
      lastOnline: DateTime.parse(json['last_online'] ?? DateTime.now().toIso8601String()),
      email: json['email'] ?? '',
      info: json['info'] ?? '',
      avatar: json['avatar'] ?? '👤',
      bio: json['bio'] ?? json['info'] ?? '',
      isWorking: json['isWorking'] ?? false,
      currentProject: json['currentProject'] ?? '',
      totalSeries: json['totalSeries'] ?? 0,
      totalTracks: json['totalTracks'] ?? 0,
      joinedDate: json['joinedDate'] != null 
          ? DateTime.parse(json['joinedDate']) 
          : DateTime.parse(json['registered_at'] ?? DateTime.now().toIso8601String()),
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
    final token = dotenv.env['API_TOKEN'] ?? '';
    print('API_TOKEN from env: "$token"');
    print('All env vars: ${dotenv.env.keys.toList()}');
    
    // Fallback for development if env loading fails
    if (token.isEmpty) {
      print('WARNING: API_TOKEN is empty, using hardcoded fallback');
      return 'asdfasdasduiu546'; // This should work since it matches server
    }
    
    return token;
  }

  static Future<UserProfilesResponse> getUserProfiles({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      // Try to reload dotenv if token is empty
      if (dotenv.env['API_TOKEN']?.isEmpty ?? true) {
        print('API_TOKEN is empty, reloading dotenv...');
        await dotenv.load(fileName: ".env");
      }
      
      final token = _apiToken;
      print('Using token: "$token"');
      
      final queryParams = {
        'token': token,
        'limit': limit.toString(),
        'offset': offset.toString(),
      };
      print('Query params: $queryParams');
      
      final url = Uri.parse('$_baseUrl/users/profiles')
          .replace(queryParameters: queryParams);

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

  static Future<List<UserSeries>> getUserSeries(String userId) async {
    try {
      final url = Uri.parse('$_baseUrl/soundseries/user')
          .replace(queryParameters: {
        'user_id': userId,
        'token': _apiToken,
        'limit': '20',
        'offset': '0',
      });

      print('Fetching user series from: $url');

      final response = await http.get(url);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        final soundseriesList = jsonData['soundseries'] as List<dynamic>? ?? [];
        
        return soundseriesList.map((soundseries) => UserSeries.fromJson(soundseries)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else {
        throw Exception('Failed to load user series: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user series: $e');
      throw Exception('Network error: $e');
    }
  }

  static Future<SoundSeriesData> getSoundSeries(String seriesId) async {
    try {
      final url = Uri.parse('$_baseUrl/soundseries')
          .replace(queryParameters: {
        'id': seriesId,
        'token': _apiToken,
      });

      print('Fetching sound series from: $url');

      final response = await http.get(url);

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        return SoundSeriesData.fromJson(jsonData);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid API token');
      } else if (response.statusCode == 404) {
        throw Exception('Sound series not found');
      } else {
        throw Exception('Failed to load sound series: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching sound series: $e');
      throw Exception('Network error: $e');
    }
  }
}

// Data models
class UserSeries {
  final String id;
  final String title;
  final String description;
  final int trackCount;
  final Duration duration;
  final DateTime createdDate;
  final bool isPublic;
  final String genre;
  final int coverColor;
  final bool isLocked;

  UserSeries({
    required this.id,
    required this.title,
    required this.description,
    required this.trackCount,
    required this.duration,
    required this.createdDate,
    required this.isPublic,
    required this.genre,
    required this.coverColor,
    required this.isLocked,
  });

  factory UserSeries.fromJson(Map<String, dynamic> json) {
    final audioData = json['audio'] as Map<String, dynamic>? ?? {};
    
    return UserSeries(
      id: json['id'] ?? '',
      title: json['name'] ?? '',
      description: json['description'] ?? '',
      trackCount: json['track_count'] ?? 0,
      duration: Duration(seconds: (audioData['duration'] ?? 0).round()),
      createdDate: DateTime.parse(json['created'] ?? DateTime.now().toIso8601String()),
      isPublic: json['visibility'] == 'public',
      genre: json['genre'] ?? 'Unknown',
      coverColor: json['cover_color'] ?? 0xFF9CA3AF,
      isLocked: json['edit_lock'] ?? false,
    );
  }
}

class SoundSeriesData {
  final String seriesId;
  final String title;
  final List<SoundTrack> sounds;
  final int bpm;
  final String key;
  final DateTime createdDate;
  final List<AudioRender> renders;
  final List<AudioSource> sources;

  SoundSeriesData({
    required this.seriesId,
    required this.title,
    required this.sounds,
    required this.bpm,
    required this.key,
    required this.createdDate,
    required this.renders,
    required this.sources,
  });

  factory SoundSeriesData.fromJson(Map<String, dynamic> json) {
    final audioData = json['audio'] as Map<String, dynamic>? ?? {};
    final soundsList = audioData['sounds'] as List<dynamic>? ?? [];
    final rendersList = audioData['renders'] as List<dynamic>? ?? [];
    final sourcesList = audioData['sources'] as List<dynamic>? ?? [];

    return SoundSeriesData(
      seriesId: json['id'] ?? '',
      title: json['name'] ?? '',
      sounds: soundsList.map((sound) => SoundTrack.fromJson(sound)).toList(),
      bpm: audioData['bpm'] ?? 120,
      key: audioData['key'] ?? 'C Major',
      createdDate: DateTime.parse(json['created'] ?? DateTime.now().toIso8601String()),
      renders: rendersList.map((render) => AudioRender.fromJson(render)).toList(),
      sources: sourcesList.map((source) => AudioSource.fromJson(source)).toList(),
    );
  }
}

class SoundTrack {
  final String id;
  final String name;
  final String url;
  final Duration duration;

  SoundTrack({
    required this.id,
    required this.name,
    required this.url,
    required this.duration,
  });

  factory SoundTrack.fromJson(Map<String, dynamic> json) {
    return SoundTrack(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      duration: Duration(seconds: json['duration_seconds'] ?? 0),
    );
  }
}

class AudioRender {
  final String id;
  final String url;
  final String createdAt;
  final String version;
  final String quality;

  AudioRender({
    required this.id,
    required this.url,
    required this.createdAt,
    required this.version,
    required this.quality,
  });

  factory AudioRender.fromJson(Map<String, dynamic> json) {
    return AudioRender(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      createdAt: json['created_at'] ?? '',
      version: json['version'] ?? '',
      quality: json['quality'] ?? '',
    );
  }
}

class AudioSource {
  final List<GridData> gridStacks;
  final List<SampleData> samples;

  AudioSource({
    required this.gridStacks,
    required this.samples,
  });

  factory AudioSource.fromJson(Map<String, dynamic> json) {
    final gridStacksList = json['grid_stacks'] as List<dynamic>? ?? [];
    final samplesList = json['samples'] as List<dynamic>? ?? [];
    
    return AudioSource(
      gridStacks: gridStacksList.map((grid) => GridData.fromJson(grid)).toList(),
      samples: samplesList.map((sample) => SampleData.fromJson(sample)).toList(),
    );
  }
}

class GridData {
  final List<List<GridCell>> layers;
  final GridMetadata metadata;

  GridData({
    required this.layers,
    required this.metadata,
  });

  factory GridData.fromJson(Map<String, dynamic> json) {
    final layersList = json['layers'] as List<dynamic>? ?? [];
    
    return GridData(
      layers: layersList.map((layer) {
        final layerCells = layer as List<dynamic>;
        return layerCells.map((cell) => GridCell.fromJson(cell)).toList();
      }).toList(),
      metadata: GridMetadata.fromJson(json['metadata'] ?? {}),
    );
  }
}

class GridMetadata {
  final String user;
  final String createdAt;
  final int bpm;
  final String key;
  final String timeSignature;

  GridMetadata({
    required this.user,
    required this.createdAt,
    required this.bpm,
    required this.key,
    required this.timeSignature,
  });

  factory GridMetadata.fromJson(Map<String, dynamic> json) {
    return GridMetadata(
      user: json['user'] ?? '',
      createdAt: json['created_at'] ?? '',
      bpm: json['bpm'] ?? 120,
      key: json['key'] ?? 'C Major',
      timeSignature: json['time_signature'] ?? '4/4',
    );
  }
}

class GridCell {
  final String? sampleId;
  final String? sampleName;

  GridCell({
    this.sampleId,
    this.sampleName,
  });

  factory GridCell.fromJson(Map<String, dynamic> json) {
    return GridCell(
      sampleId: json['sample_id'],
      sampleName: json['sample_name'],
    );
  }

  bool get isEmpty => sampleId == null || sampleId!.isEmpty;
}

class SampleData {
  final String id;
  final String name;
  final String url;
  final bool isPublic;

  SampleData({
    required this.id,
    required this.name,
    required this.url,
    required this.isPublic,
  });

  factory SampleData.fromJson(Map<String, dynamic> json) {
    return SampleData(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      url: json['url'] ?? '',
      isPublic: json['is_public'] ?? false,
    );
  }
} 