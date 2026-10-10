import 'package:dio/dio.dart';

/// For external APIs (Radio-Browser, Telegram getMe). Doesn't attach the device token.
Dio createExternalHttp() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      // Radio-Browser requires a User-Agent
      headers: {'User-Agent': 'AISpeakerApp/1.0'},
    ));
