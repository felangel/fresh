// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';

const getJobsQuery = '''
  query GetJobs() {
    jobs {
      title
    }
  }
''';

// Mock storage for issuedAt
int? issuedAt;

// Simulate storing issuedAt when the token is set
Future<void> storeIssuedAt(int issuedTime) async {
  print('Storing issuedAt: $issuedTime');
  issuedAt = issuedTime;
}

// Simulate fetching issuedAt from storage
Future<int?> fetchIssuedAt() async {
  print('Fetching issuedAt...');
  return issuedAt;
}

/// Returns the current Unix time in seconds (since January 1, 1970, UTC).
int currentUnixTime() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() async {
  final freshLink = FreshLink.oAuth2(
    tokenStorage: InMemoryTokenStorage(),
    refreshToken: (token, client) async {
      // Perform refresh and return new token
      print('refreshing token!');
      await Future<void>.delayed(const Duration(seconds: 1));
      if (Random().nextInt(2) == 0) {
        throw RevokeTokenException();
      }
      final newIssuedAt = currentUnixTime();
      await storeIssuedAt(newIssuedAt);
      return const OAuth2Token(accessToken: 'refreshed_token!', expiresIn: 30);
    },
    shouldRefresh: (_) => Random().nextInt(2) == 0,
    shouldRefreshBeforeRequest: (token) async {
      print('Checking token validity before request...');
      final now = currentUnixTime();
      final storedIssuedAt = await fetchIssuedAt();
      if (token?.expiresIn != null && storedIssuedAt != null) {
        return (storedIssuedAt + token!.expiresIn!) < now;
      }
      return false;
    },
  )..authenticationStatus.listen(print);

  // Set the initial token and store issuedAt
  final initialIssuedAt = currentUnixTime();
  await storeIssuedAt(initialIssuedAt);

  await freshLink.setToken(
    const OAuth2Token(
      accessToken: 't0ps3cret!',
      expiresIn: 30,
    ),
  );

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
