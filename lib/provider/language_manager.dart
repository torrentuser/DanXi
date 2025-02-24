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

import 'dart:ui';

import 'package:dan_xi/common/constant.dart';
import 'package:flutter/material.dart';

class LanguageManager {
  /// Convert the [Language] to language code for [Locale].
  static Locale toLocale(Language language) {
    if (language == Language.SIMPLE_CHINESE) return const Locale("zh", "CN");
    if (language == Language.ENGLISH) return const Locale("en");
    if (language == Language.JAPANESE) return const Locale("ja");
    return const Locale("en");
  }
}
