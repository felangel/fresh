import 'dart:math';

import 'package:example/api/api.dart';
import 'package:example/api/queries/queries.dart' as queries;
import 'package:flutter/foundation.dart';
import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';

class GetJobsRequestFailure implements Exception {}

class JobsApiClient {
  const JobsApiClient(
      {@required GraphQLClient graphQLClient, @required FreshLink freshLink})
      : assert(graphQLClient != null),
        assert(freshLink != null),
        _graphQLClient = graphQLClient,
        _freshLink = freshLink;

  factory JobsApiClient.create() {
    final httpLink = HttpLink(uri: 'https://api.graphql.jobs');
    final cache = InMemoryCache();
    final freshLink = FreshLink(
      tokenStorage: InMemoryTokenStorage(),
      refreshToken: (token, client) async {
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
      },
      shouldRefresh: (_) => Random().nextInt(3) == 0,
    );
    final link = Link.from([freshLink, httpLink]);
    return JobsApiClient(
      graphQLClient: GraphQLClient(cache: cache, link: link),
      freshLink: freshLink,
    );
  }

  static int _refreshCount = 0;
  final GraphQLClient _graphQLClient;
  final FreshLink _freshLink;

  Future<void> setToken(OAuth2Token token) => _freshLink.setToken(token);

  Future<List<Job>> getJobs() async {
    final result = await _graphQLClient.query(
      QueryOptions(
        documentNode: gql(queries.getJobs),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) {
      throw GetJobsRequestFailure();
    }

    final data = result.data['jobs'] as List;
    return data.map((e) => Job.fromJson(e)).toList();
  }
}
