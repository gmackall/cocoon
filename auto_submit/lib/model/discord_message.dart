// Copyright 2024 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:json_annotation/json_annotation.dart';

part 'discord_message.g.dart';

@JsonSerializable()
class Message {
  Message({this.content, this.username, this.avatarUrl});

  String? content;
  String? username;
  // avatar_url
  @JsonKey(name: 'avatar_url', includeIfNull: false)
  String? avatarUrl;

  factory Message.fromJson(Map<String, dynamic> input) =>
      _$MessageFromJson(input);
  Map<String, dynamic> toJson() => _$MessageToJson(this);
}
