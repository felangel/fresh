import 'dart:io';
import 'dart:math';

import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';

const getJobsQuery = r'''
  query GetJobs() {
    jobs {
      title
    }
  }
''';

void main() async {
  final freshLink = FreshLink<OAuth2Token>(
    tokenStorage: InMemoryTokenStorage(),
    refreshToken: (token, client) async {
      // Perform refresh and return new token
      print('refreshing token!');
      await Future.delayed(const Duration(seconds: 1));
      if (Random().nextInt(3) == 0) {
        throw RevokeTokenException();
      }
      return OAuth2Token(accessToken: 't0ps3cret_r3fresh3d!');
    },
    shouldRefresh: (_) => Random().nextInt(1) == 0,
    onRefreshFailure: () => print('refresh failed!'),
  )..setToken(OAuth2Token(accessToken: 't0ps3cret!'));
  final graphQLClient = GraphQLClient(
    cache: InMemoryCache(),
    link: Link.from([freshLink, HttpLink(uri: 'https://api.graphql.jobs')]),
  );
  final result = await graphQLClient.query(
    QueryOptions(documentNode: gql(getJobsQuery)),
  );
  print(result.data);
  exit(0);
}
