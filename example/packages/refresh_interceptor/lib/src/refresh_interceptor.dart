import 'dart:math';
import 'package:fresh/fresh.dart';

import 'in_memory_token_storage.dart';

class RefreshInterceptor extends FreshInterceptor<OAuth2Token> {
  RefreshInterceptor() : super(InMemoryTokenStorage());

  var _refreshCount = 0;

  @override
  Future<OAuth2Token> refreshToken(_, __) async {
    print('refreshing token...');
    await Future.delayed(const Duration(seconds: 1));
    if (Random().nextInt(3) == 0) {
      print('token revoked!');
      throw RevokeTokenException();
    }
    print('token refreshed!');
    _refreshCount++;
    return OAuth2Token(
      accessToken: 'access_token_$_refreshCount',
      refreshToken: 'refresh_token_$_refreshCount',
    );
  }

  @override
  bool shouldRefresh(_) => Random().nextInt(3) == 0;
}
