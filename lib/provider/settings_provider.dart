/*
 *     Copyright (C) 2021  w568w
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

import 'package:dan_xi/common/constant.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider {
  SharedPreferences _preferences;

  static const String KEY_PREFERRED_CAMPUS = "campus";

  SettingsProvider._(this._preferences);

  factory SettingsProvider.of(SharedPreferences preferences) {
    return SettingsProvider._(preferences);
  }

  Campus get campus {
    if (_preferences.containsKey(KEY_PREFERRED_CAMPUS)) {
      String value = _preferences.getString(KEY_PREFERRED_CAMPUS);
      return Constant.CAMPUS_VALUES
          .firstWhere((element) => element.toString() == value, orElse: () {
        campus = Campus.HANDAN_CAMPUS;
        return Campus.HANDAN_CAMPUS;
      });
    }
    campus = Campus.HANDAN_CAMPUS;
    return Campus.HANDAN_CAMPUS;
  }

  set campus(Campus campus) {
    _preferences.setString(KEY_PREFERRED_CAMPUS, campus.toString());
  }
}
