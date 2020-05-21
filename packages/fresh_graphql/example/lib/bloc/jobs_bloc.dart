import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:example/api/api.dart';
import 'package:example/api/job_api_client.dart';
import 'package:meta/meta.dart';

part 'jobs_event.dart';
part 'jobs_state.dart';

class JobsBloc extends Bloc<JobsEvent, JobsState> {
  JobsBloc({@required JobsApiClient jobsApiClient})
      : assert(jobsApiClient != null),
        _jobsApiClient = jobsApiClient;

  final JobsApiClient _jobsApiClient;

  @override
  JobsState get initialState => JobsLoadInProgress();

  @override
  void onTransition(Transition<JobsEvent, JobsState> transition) {
    print(transition);
    super.onTransition(transition);
  }

  @override
  Stream<JobsState> mapEventToState(
    JobsEvent event,
  ) async* {
    if (event is JobsFetchStarted) {
      yield JobsLoadInProgress();
      try {
        final jobs = await _jobsApiClient.getJobs();
        yield JobsLoadSuccess(jobs);
      } on Exception catch (_) {
        yield JobsLoadFailure();
      }
    }
  }
}
