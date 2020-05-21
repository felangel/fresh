import 'package:fresh_graphql/fresh_graphql.dart';
import 'package:graphql/client.dart';

const getJobsQuery = r'''
  query GetJobs() {
    jobs {
      id,
      title,
      locationNames,
      isFeatured
    }
  }
''';

void main() async {
  final freshLink = FreshLink<OAuth2Token>(
    tokenStorage: InMemoryTokenStorage(),
    refreshToken: (token, client) async {
      // Perform refresh and return new token
      return token;
    },
  );
  final graphQLClient = GraphQLClient(
    cache: InMemoryCache(),
    link: Link.from([freshLink, HttpLink(uri: 'https://api.graphql.jobs')]),
  );
  await graphQLClient.query(
    QueryOptions(documentNode: gql(getJobsQuery)),
  );
}
