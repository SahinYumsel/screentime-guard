import 'package:dio/dio.dart';

import '../data/local_store.dart';
import '../domain/rule.dart';
import '../domain/usage_record.dart';

/// Backend'in standart {"error": {"code": "...", "message": "..."}} hata yapısını temsil eder.
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => '[$code] $message';
}

/// Mikroservis ile HTTP iletişimini yürüten Dio sarmalayıcısı.
/// Her isteğe otomatik olarak `X-Device-Token` başlığını ekler.
class ApiClient {
  final LocalStore _localStore;
  late final Dio _dio;

  ApiClient(this._localStore) {
    _dio = Dio(
      BaseOptions(
        baseUrl: _localStore.getApiBaseUrl(),
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: const {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Kullanıcı ayarlardan sunucu IP'sini güncellediyse dinamik olarak uygula
          options.baseUrl = _localStore.getApiBaseUrl();

          final token = _localStore.getDeviceToken();
          if (token != null && token.isNotEmpty) {
            options.headers['X-Device-Token'] = token;
          }
          handler.next(options);
        },
      ),
    );
  }

  /// Dio hatalarını backend'in standart hata formatına çevirir.
  ApiException _mapDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final err = data['error'] as Map<String, dynamic>;
      return ApiException(
        code: (err['code'] ?? 'API_ERROR').toString(),
        message: (err['message'] ?? 'Sunucu hatası oluştu.').toString(),
        statusCode: error.response?.statusCode,
      );
    }
    return ApiException(
      code: 'NETWORK_ERROR',
      message: error.message ?? 'Sunucuya bağlanılamadı (Çevrimdışı mod).',
      statusCode: error.response?.statusCode,
    );
  }

  /// GET /v1/health
  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/health');
      return response.statusCode == 200 && response.data?['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// POST /v1/devices — Cihaz kaydı yapar ve {device_id, token} döndürür.
  Future<Map<String, dynamic>> registerDevice({required String name}) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/devices',
        data: {'name': name},
      );
      return response.data!;
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// GET /v1/rules — Cihazın mevcut kuralını getirir.
  Future<Rule> fetchRule() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/v1/rules');
      return Rule.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// PUT /v1/rules — Cihazın kuralını günceller.
  Future<Rule> updateRule(Rule rule) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/v1/rules',
        data: rule.toUpdateJson(),
      );
      return Rule.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// POST /v1/usage — Günlük kullanım verisini gönderir (idempotent).
  Future<UsageRecord> postUsage(UsageRecord record) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/v1/usage',
        data: record.toJson(),
      );
      return UsageRecord.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// GET /v1/usage?days=7 — Haftalık kullanım geçmişini ve ortalamayı getirir.
  Future<UsageHistory> fetchUsageHistory({int days = 7}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/usage',
        queryParameters: {'days': days},
      );
      return UsageHistory.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }
}
