// Copyright 2022 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:googleapis/bigquery/v2.dart';

import 'big_query_pull_request_record.dart';
import 'google_auth_provider.dart';

const String _insertPullRequestDml = r'''
INSERT INTO `flutter-dashboard.autosubmit.pull_requests` (
  pr_created_timestamp,
  pr_landed_timestamp,
  organization,
  repository,
  author,
  pr_number,
  pr_commit,
  pr_request_type
) VALUES (
  @PR_CREATED_TIMESTAMP,
  @PR_LANDED_TIMESTAMP,
  @ORGANIZATION,
  @REPOSITORY,
  @AUTHOR,
  @PR_NUMBER,
  @PR_COMMIT,
  @PR_REQUEST_TYPE
)
''';

class BigqueryService {
  /// Creates a [BigqueryService] using Google API authentication.
  static Future<BigqueryService> from(GoogleAuthProvider authProvider) async {
    final client = await authProvider.createClient(
      scopes: const [BigqueryApi.bigqueryScope],
    );
    return BigqueryService.forTesting(BigqueryApi(client).jobs);
  }

  const BigqueryService.forTesting(this._defaultJobs);
  final JobsResource _defaultJobs;

  /// Insert a new pull request record into the database.
  Future<void> insertPullRequestRecord({
    required String projectId,
    required PullRequestRecord pullRequestRecord,
  }) async {
    final queryRequest = QueryRequest(
      query: _insertPullRequestDml,
      queryParameters: <QueryParameter>[
        _createIntegerQueryParameter(
          'PR_CREATED_TIMESTAMP',
          pullRequestRecord.prCreatedTimestamp!.millisecondsSinceEpoch,
        ),
        _createIntegerQueryParameter(
          'PR_LANDED_TIMESTAMP',
          pullRequestRecord.prLandedTimestamp!.millisecondsSinceEpoch,
        ),
        _createStringQueryParameter(
          'ORGANIZATION',
          pullRequestRecord.organization,
        ),
        _createStringQueryParameter('REPOSITORY', pullRequestRecord.repository),
        _createStringQueryParameter('AUTHOR', pullRequestRecord.author),
        _createIntegerQueryParameter('PR_NUMBER', pullRequestRecord.prNumber),
        _createStringQueryParameter('PR_COMMIT', pullRequestRecord.prCommit),
        _createStringQueryParameter(
          'PR_REQUEST_TYPE',
          pullRequestRecord.prRequestType,
        ),
      ],
      useLegacySql: false,
    );

    final queryResponse = await _defaultJobs.query(queryRequest, projectId);
    if (!queryResponse.jobComplete!) {
      throw BigQueryException(
        'Insert pull request $pullRequestRecord did not complete.',
      );
    }

    if (queryResponse.numDmlAffectedRows != null &&
        int.parse(queryResponse.numDmlAffectedRows!) != 1) {
      throw BigQueryException(
        'There was an error inserting $pullRequestRecord into the table.',
      );
    }
  }

  /// Create an int parameter for query substitution.
  QueryParameter _createIntegerQueryParameter(String name, int? value) {
    return QueryParameter(
      name: name,
      parameterType: QueryParameterType(type: 'INT64'),
      parameterValue: QueryParameterValue(value: value.toString()),
    );
  }

  /// Create a String parameter for query substitution.
  QueryParameter _createStringQueryParameter(String name, String? value) {
    return QueryParameter(
      name: name,
      parameterType: QueryParameterType(type: 'STRING'),
      parameterValue: QueryParameterValue(value: value),
    );
  }
}

class BigQueryException implements Exception {
  /// Create a custom exception for Big Query Errors.
  BigQueryException(this.cause);

  final String cause;

  @override
  String toString() => cause;
}
