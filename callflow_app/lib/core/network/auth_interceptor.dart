import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(Dio dio);

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static const _accessTokenKey = 'access_token';

  static const _publicPaths = [
    '/auth/register',
    '/auth/login',
    '/app/version',
    '/health',
  ];

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final isPublic = _publicPaths.any((p) => options.path.contains(p));
    if (isPublic) {
      return handler.next(options);
    }

    _storage.read(key: _accessTokenKey).then((token) {
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }).catchError((e) {
      // Storage corrupted — proceed without auth, user will be redirected to login
      handler.next(options);
    });
  }

  static Future<void> saveToken(String accessToken) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
  }

  static Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  static Future<bool> hasTokens() async {
    try {
      final token = await _storage.read(key: _accessTokenKey);
      return token != null;
    } catch (_) {
      // Secure storage corrupted (e.g. Android Keystore key invalidated).
      // Clear everything and treat as logged-out.
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return false;
    }
  }
}
