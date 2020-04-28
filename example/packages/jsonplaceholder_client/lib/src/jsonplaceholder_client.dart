import 'package:dio/dio.dart';
import 'package:refresh_interceptor/refresh_interceptor.dart';
import 'package:jsonplaceholder_client/jsonplaceholder_client.dart';
import 'package:meta/meta.dart';

class PhotosRequestFailureException implements Exception {}

class JsonplaceholderClient {
  JsonplaceholderClient({Dio httpClient})
      : _httpClient = httpClient ?? Dio()
          ..options.baseUrl = 'https://jsonplaceholder.typicode.com'
          ..interceptors.add(_refreshInterceptor);

  final Dio _httpClient;
  static final RefreshInterceptor _refreshInterceptor = RefreshInterceptor();

  Stream<AuthenticationStatus> get authenticationStatus =>
      _refreshInterceptor.authenticationStatus;

  Future<void> authenticate({
    @required String username,
    @required String password,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    await _refreshInterceptor.setToken(
      OAuth2Token(
        accessToken: 'initial_access_token',
        refreshToken: 'initial_refresh_token',
      ),
    );
  }

  Future<void> unauthenticate() async {
    await Future.delayed(const Duration(seconds: 1));
    await _refreshInterceptor.setToken(null);
  }

  Future<List<Photo>> photos() async {
    final response = await _httpClient.get('/photos');

    if (response.statusCode != 200) {
      throw PhotosRequestFailureException();
    }

    return (response.data as List).map((item) => Photo.fromJson(item)).toList();
  }
}
