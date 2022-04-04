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
  final freshLink = FreshLink.oAuth2(
    tokenStorage: InMemoryTokenStorage(),
    refreshToken: (token, client) async {
      // Perform refresh and return new token
      print('refreshing token!');
      await Future<void>.delayed(const Duration(seconds: 1));
      if (Random().nextInt(1) == 0) {
        throw RevokeTokenException();
      }
      return const OAuth2Token(accessToken: 't0ps3cret_r3fresh3d!');
    },
    shouldRefresh: (_) => Random().nextInt(2) == 0,
  )..authenticationStatus.listen(print);
  await freshLink.setToken(const OAuth2Token(accessToken: 't0ps3cret!'));
  final graphQLClient = GraphQLClient(
    cache: GraphQLCache(),
    link: Link.from([freshLink, HttpLink('https://api.graphql.jobs')]),
  );
  final result = await graphQLClient.query<dynamic>(
    QueryOptions<dynamic>(document: gql(getJobsQuery)),
  );
  print(result.data);
  exit(0);
}
