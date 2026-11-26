import 'package:flutter/foundation.dart';

/// Em debug: localhost. Em release sem `--dart-define`: API de produção.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kReleaseMode
      ? 'https://api.meuatendeai.com.br'
      : 'http://localhost:8000',
);