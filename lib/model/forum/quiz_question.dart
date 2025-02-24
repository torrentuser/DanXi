/*
 *     Copyright (C) 2025  DanXi-Dev
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:json_annotation/json_annotation.dart';

part 'quiz_question.g.dart';

// Represents a question in the quiz popped out after register
@JsonSerializable()
class QuizQuestion {
  String? analysis;
  List<String>? answer;
  String? group;
  int? id;
  List<String>? options;
  String? question;
  String? type;

  // Client-side info, disable serialization
  @JsonKey(includeFromJson: false, includeToJson: false)
  bool correct = false;

  factory QuizQuestion.fromJson(Map<String, dynamic> json) =>
      _$QuizQuestionFromJson(json);

  Map<String, dynamic> toJson() => _$QuizQuestionToJson(this);

  QuizQuestion(this.analysis, this.answer, this.group, this.id, this.options,
      this.question, this.type);
}
