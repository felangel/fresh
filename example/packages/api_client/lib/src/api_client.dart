import 'dart:math';
import 'package:fresh/fresh.dart';

import 'in_memory_token_storage.dart';

class ApiClient extends FreshClient<OAuth2Token> {
  ApiClient() : super(InMemoryTokenStorage());

  var refreshCount = 0;

  @override
  Future<OAuth2Token> refreshToken(_, __) async {
    print('refreshing token...');
    await Future.delayed(const Duration(seconds: 1));
    if (Random().nextInt(3) == 0) {
      print('token revoked!');
      throw RevokeTokenException();
    }
    print('token refreshed!');
    refreshCount++;
    return OAuth2Token(
      accessToken: 'access_token_$refreshCount',
      refreshToken: 'refresh_token_$refreshCount',
    );
  }

  @override
  bool shouldRefresh(_) => Random().nextInt(3) == 0;

  @override
  Map<String, String> tokenHeader(token) {
    return {
      'authorization': 'bearer ${token.accessToken}',
    };
  }
}
