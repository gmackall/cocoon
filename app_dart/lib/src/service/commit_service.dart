// Copyright 2021 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:github/github.dart' as gh;
import 'package:github/hooks.dart' as gh;
import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:meta/meta.dart';
import 'package:truncate/truncate.dart';

import '../model/firestore/commit.dart' as fs;
import 'config.dart';
import 'firestore.dart';

/// Converts and stores GitHub-originated commits into Firestore.
interface class CommitService {
  CommitService({
    required Config config,
    required FirestoreService firestore,
    @visibleForTesting DateTime Function() now = DateTime.now,
  }) : _config = config,
       _firestore = firestore,
       _now = now;

  final Config _config;
  final FirestoreService _firestore;
  final DateTime Function() _now;

  /// Add a commit based on a [CreateEvent] to the Firestore.
  Future<void> handleCreateGithubRequest(gh.CreateEvent createEvent) async {
    // Extract some information from the event.
    final slug = gh.RepositorySlug.full(createEvent.repository!.fullName);
    final branch = createEvent.ref!;

    // Fetch the ToT commit SHA for the branch.
    final githubService = await _config.createDefaultGitHubService();
    final gitRef = await githubService.getReference(slug, 'heads/$branch');
    final sha = gitRef.object!.sha!;
    final ghCommit = await githubService.github.repositories.getCommit(
      slug,
      sha,
    );

    // Convert into the format the rest of the service uses.
    await _insertFirestore(
      _Commit.fromBranchEvent(
        repository: slug,
        branch: branch,
        commit: ghCommit,
        now: _now(),
      ),
    );
  }

  /// Add a commit based on a Push event to the Firestore.
  /// https://docs.github.com/en/webhooks/webhook-events-and-payloads#push
  Future<void> handlePushGithubRequest(Map<String, Object?> pushEvent) async {
    await _insertFirestore(_Commit.fromPushEventJson(pushEvent));
  }

  Future<void> _insertFirestore(_Commit commit) async {
    final fsCommit = fs.Commit(
      createTimestamp: commit.createdOn.millisecondsSinceEpoch,
      repositoryPath: commit.repository.fullName,
      sha: commit.sha,
      author: commit.author,
      avatar: commit.avatar,
      message: commit.message,
      branch: commit.branch,
    );
    await _firestore.batchWriteDocuments(
      fs.BatchWriteRequest(writes: documentsToWrites([fsCommit])),
      kDatabase,
    );
  }
}

/// A commit that is database and origin agnostic.
final class _Commit {
  _Commit._({
    required this.repository,
    required this.author,
    required this.avatar,
    required this.branch,
    required this.sha,
    required this.createdOn,
    required this.message,
  });

  factory _Commit.fromBranchEvent({
    required gh.RepositorySlug repository,
    required String branch,
    required gh.RepositoryCommit commit,
    required DateTime now,
  }) {
    return _Commit._(
      repository: repository,
      author: commit.author!.login!,
      avatar: commit.author!.avatarUrl!,
      branch: branch,
      sha: commit.sha!,
      createdOn: now,
      message: truncate(commit.commit!.message!, 1490, omission: '...'),
    );
  }

  factory _Commit.fromPushEventJson(Map<String, Object?> json) {
    if (json case {
      'repository': {'full_name': final String fullName},
      'head_commit': {
        'id': final String sha,
        'message': final String message,
        'timestamp': final String timestamp,
      },
      'ref': final String ref,
      'sender': {
        'login': final String author,
        'avatar_url': final String avatar,
      },
    }) {
      return _Commit._(
        repository: gh.RepositorySlug.full(fullName),
        author: author,
        avatar: avatar,
        branch: ref.split('/')[2],
        sha: sha,
        createdOn: DateTime.parse(timestamp),
        message: truncate(message, 1490, omission: '...'),
      );
    }
    throw FormatException('Invalid JSON for commit: $json');
  }

  /// Which repository this commit belongs to.
  final gh.RepositorySlug repository;

  /// The author of the commit.
  final String author;

  /// The avatar of the author.
  final String avatar;

  /// The branch this commit belongs to.
  final String branch;

  /// The SHA of the commit.
  final String sha;

  /// The date this commit was created.
  final DateTime createdOn;

  /// The commit message, possibly truncated.
  final String message;
}
