/*
 *     Copyright (C) 2021  DanXi-Dev
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

import 'dart:convert';
import 'dart:io';

import 'package:asn1lib/asn1lib.dart';
import 'package:dan_xi/common/Secret.dart';
import 'package:dan_xi/common/constant.dart';
import 'package:dan_xi/model/opentreehole/division.dart';
import 'package:dan_xi/model/opentreehole/floor.dart';
import 'package:dan_xi/model/opentreehole/hole.dart';
import 'package:dan_xi/model/opentreehole/tag.dart';
import 'package:dan_xi/model/opentreehole/user.dart';
import 'package:dan_xi/model/person.dart';
import 'package:dan_xi/model/report.dart';
import 'package:dan_xi/provider/settings_provider.dart';
import 'package:dan_xi/repository/base_repository.dart';
import 'package:dan_xi/util/platform_bridge.dart';
import 'package:dan_xi/widget/libraries/paged_listview.dart';
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class OpenTreeHoleRepository extends BaseRepositoryWithDio {
  static final _instance = OpenTreeHoleRepository._();

  factory OpenTreeHoleRepository.getInstance() => _instance;

  static const String _BASE_URL = "https://hole.hath.top";

  /// The token used for session authentication.
  String? _token;

  /// Current user profile, stored as cache by the repository
  OTUser? _userInfo;

  /// Cached floors, used by [mentions]
  List<OTFloor> _floorCache = [];

  /// Cached divisions
  List<OTDivision> _divisionCache = [];

  /// Push Notification Registration Cache
  String? _deviceId, _pushNotificationToken;
  PushNotificationServiceType? _pushNotificationService;

  void clearCache() {
    _token = null;
    _userInfo = null;
    _deviceId = null;
    _pushNotificationService = null;
    _pushNotificationToken = null;
  }

  OpenTreeHoleRepository._() {
    // Override the options set in parent class.
    dio!.options = BaseOptions(receiveDataWhenStatusError: true);
  }

  Future<void> initializeRepo() async {
    print(
        "WARNING: Certificate Pinning Disabled. Do not use for production builds.");
    try {
      PlatformBridge.requestNotificationPermission();
    } catch (ignored) {}
    if (SettingsProvider.getInstance().fduholeToken != null) {
      _token = SettingsProvider.getInstance().fduholeToken;
    } else {
      throw NotLoginError("No token");
      // _token = await requestToken(info!);
      // updatePushNotificationToken();
    }
    _divisionCache = await loadDivisions();
  }

  Future<bool> checkRegisterStatus(String email) async {
    Response response = await dio!.get(_BASE_URL + "/verify/apikey",
        queryParameters: {
          "apikey": Secret.FDUHOLE_API_KEY,
          "email": email,
          "check_register": 1,
        },
        options: Options(validateStatus: (code) => code! <= 409));
    return response.statusCode == 409;
  }

  Future<String?> getVerifyCode(String email) async {
    Response response = await dio!.get(_BASE_URL + "/verify/apikey",
        queryParameters: {
          "apikey": Secret.FDUHOLE_API_KEY,
          "email": email,
        },
        options: Options(validateStatus: (code) => code! < 300));
    final json =
        response.data is Map ? response.data : jsonDecode(response.data);
    return json["code"].toString();
  }

  Future<void> requestEmailVerifyCode(String email) async {
    await dio!
        .get(_BASE_URL + "/verify/email", queryParameters: {"email": email});
  }

  Future<String?> register(
      String email, String password, String verifyCode) async {
    final Response response = await dio!.post(_BASE_URL + "/register", data: {
      "password": password,
      "email": email,
      "verification": int.parse(verifyCode),
    });
    return SettingsProvider.getInstance().fduholeToken = response.data["token"];
  }

  Future<String> loginWithUsernamePassword(
      String username, String password) async {
    final Response response = await dio!.post(_BASE_URL + "/login", data: {
      'email': username,
      'password': password,
    });
    return SettingsProvider.getInstance().fduholeToken = response.data["token"];
  }

  Future<String?> requestToken(PersonInfo info) async {
    Dio secureDio = Dio();
    //Pin HTTPS cert
    (secureDio.httpClientAdapter as DefaultHttpClientAdapter)
        .onHttpClientCreate = (client) {
      final SecurityContext sc = SecurityContext(withTrustedRoots: false);
      HttpClient httpClient = HttpClient(context: sc);
      httpClient.badCertificateCallback =
          (X509Certificate certificate, String host, int port) {
        return true;
        // This badCertificateCallback will always be called since we have no trusted certificate.
        final ASN1Parser p = ASN1Parser(certificate.der);
        final ASN1Sequence signedCert = p.nextObject() as ASN1Sequence;
        final ASN1Sequence cert = signedCert.elements[0] as ASN1Sequence;
        final ASN1Sequence pubKeyElement = cert.elements[6] as ASN1Sequence;
        final ASN1BitString pubKeyBits =
            pubKeyElement.elements[1] as ASN1BitString;

        if (listEquals(
            pubKeyBits.stringValue, SecureConstant.PINNED_CERTIFICATE)) {
          return true;
        }
        // Allow connection when public key matches
        throw NotLoginError("Invalid HTTPS Certificate");
      };
      return httpClient;
    };
    //
    // crypto.PublicKey publicKey =
    //     RsaKeyHelper().parsePublicKeyFromPem(Secret.RSA_PUBLIC_KEY);

    final Response response =
        await secureDio.post(_BASE_URL + "/register/", data: {
      'api-key': Secret.FDUHOLE_API_KEY,
      'email': "${info.id}@fudan.edu.cn",
      // Temporarily disable v2 API until the protocol is ready.
      //'ID': base64.encode(utf8.encode(encrypt(info.id, publicKey)))
    }).onError((dynamic error, stackTrace) {
      return Future.error(error);
    });
    try {
      return SettingsProvider.getInstance().fduholeToken =
          response.data["token"];
    } catch (e) {
      return Future.error(e);
    }
  }

  Map<String, String> get _tokenHeader {
    if (_token == null) throw NotLoginError("Null Token");
    return {"Authorization": "Token " + _token!};
  }

  bool get isUserInitialized => _token != null;

  Future<List<OTDivision>> loadDivisions({bool useCache = true}) async {
    if (_divisionCache.isNotEmpty && useCache) {
      return _divisionCache;
    }
    final Response response = await dio!
        .get(_BASE_URL + "/divisions", options: Options(headers: _tokenHeader));
    final List result = response.data;
    _divisionCache = result.map((e) => OTDivision.fromJson(e)).toList();
    return _divisionCache;
  }

  List<OTDivision> getDivisions() {
    return _divisionCache;
  }

  Future<OTDivision> loadSpecificDivision(int divisionId,
      {bool useCache = true}) async {
    if (useCache) {
      try {
        final OTDivision cached =
            _divisionCache.firstWhere((e) => e.division_id == divisionId);
        return cached;
      } catch (ignored) {}
    }
    final Response response = await dio!.get(
        _BASE_URL + "/divisions/$divisionId",
        options: Options(headers: _tokenHeader));
    final result = response.data;
    final newDivision = OTDivision.fromJson(result);
    _divisionCache.removeWhere((element) => element.division_id == divisionId);
    _divisionCache.add(newDivision);
    return newDivision;
  }

  Future<List<OTHole>> loadHoles(
    DateTime startTime,
    int divisionId, {
    int length = 10,
    int prefetchLength = 10,
  }) async {
    print(divisionId);
    final Response response = await dio!.get(_BASE_URL + "/holes",
        queryParameters: {
          "start_time": startTime.toIso8601String(),
          "division_id": divisionId,
          "length": length,
          "prefetch_length": prefetchLength
        },
        options: Options(headers: _tokenHeader));
    final List result = response.data;
    return result.map((e) => OTHole.fromJson(e)).toList();
  }

  // Migrated
  Future<OTHole> loadSpecificHole(int discussionId) async {
    final Response response = await dio!.get(_BASE_URL + "/holes/$discussionId",
        options: Options(headers: _tokenHeader));
    return OTHole.fromJson(response.data);
  }

  // Migrated
  Future<OTFloor> loadSpecificFloor(int floorId) async {
    // TODO: This API should first check if the requested floor is already cached.
    // Inside [Mention]
    final Response response = await dio!.get(_BASE_URL + "/floors/$floorId",
        options: Options(headers: _tokenHeader));
    return OTFloor.fromJson(response.data);
  }

  // Do we have such an API?
  Future<List<OTHole>> loadTagFilteredDiscussions(
      String tag, SortOrder sortBy, int page) async {
    try {
      final response = await dio!.get(_BASE_URL + "/discussions/",
          queryParameters: {
            "order": sortBy.getInternalString(),
            "tag_name": tag,
            "page": page,
          },
          options: Options(headers: _tokenHeader));
      final List result = response.data;
      return result.map((e) => OTHole.fromJson(e)).toList();
    } catch (error) {
      if (error is DioError && error.response?.statusCode == 401) {
        _token = null;
        throw LoginExpiredError;
      }
      rethrow;
    }
  }

  // Migrated
  Future<List<OTFloor>> loadFloors(
      OTHole post, int startFloor, int length) async {
    final Response response = await dio!.get(_BASE_URL + "/floors",
        queryParameters: {
          "start_floor": startFloor,
          "hole_id": post.hole_id,
          "length": length
        },
        options: Options(headers: _tokenHeader));
    final List result = response.data;
    return result.map((e) => OTFloor.fromJson(e)).toList();
  }

  // Migrated
  Future<List<OTFloor>> loadSearchResults(
      String? searchString, int page) async {
    // Search results only have a single page.
    // Return nothing if [page] > 1.
    if (page > 1) return Future.value([]);
    final Response response = await dio!.get(_BASE_URL + "/floors",
        queryParameters: {"start_floor": 0, "s": searchString, "length": 0},
        options: Options(headers: _tokenHeader));
    final List result = response.data;
    return result.map((e) => OTFloor.fromJson(e)).toList();
  }

  // Migrated
  Future<List<OTTag>> loadTags() async {
    final Response response = await dio!
        .get(_BASE_URL + "/tags", options: Options(headers: _tokenHeader));
    final List result = response.data;
    return result.map((e) => OTTag.fromJson(e)).toList();
  }

  // Migrated
  Future<int?> newHole(int divisionId, String? content,
      {List<OTTag>? tags}) async {
    if (content == null) return 0;
    if (tags == null) tags = [];
    // Suppose user is logged in. He should be.
    final Response response = await dio!.post(_BASE_URL + "/holes",
        data: {
          "division_id": divisionId,
          "content": content,
          "tag_names": tags.map((e) => e.name).toList()
        },
        options: Options(headers: _tokenHeader));
    return response.statusCode;
  }

  Future<String?> uploadImage(File file) async {
    String path = file.absolute.path;
    String fileName = path.substring(path.lastIndexOf("/") + 1, path.length);
    Response response = await dio!
        .post(_BASE_URL + "/images/",
            data: FormData.fromMap({
              "img": await MultipartFile.fromFile(path, filename: fileName)
            }),
            options: Options(headers: _tokenHeader))
        .onError(((dynamic error, stackTrace) => throw ImageUploadError()));
    return response.data['url'];
  }

  // Partly migrated. What does [mention] means?
  Future<int?> newFloor(int? discussionId, int? replyTo, String content) async {
    final Response response = await dio!.post(_BASE_URL + "/floors",
        data: {
          "content": content,
          "hole_id": discussionId,
          "reply_to": replyTo
        },
        options: Options(headers: _tokenHeader));
    return response.statusCode;
  }

  // Migrated
  Future<OTFloor> likeFloor(int floorId, bool like) async {
    final Response response = await dio!.put(_BASE_URL + "/floors/$floorId",
        data: {
          "like": like ? "add" : "cancel",
        },
        options: Options(headers: _tokenHeader));
    return OTFloor.fromJson(response.data);
  }

  // Migrated
  Future<int?> reportPost(int? postId, String reason) async {
    // Suppose user is logged in. He should be.
    final Response response = await dio!.post(_BASE_URL + "/reports",
        data: {"floor_id": postId, "reason": reason},
        options: Options(headers: _tokenHeader));
    return response.statusCode;
  }

  // Migrated
  Future<OTUser?> getUserProfile({bool forceUpdate = false}) async {
    if (_userInfo == null || forceUpdate) {
      final Response response = await dio!
          .get(_BASE_URL + "/users", options: Options(headers: _tokenHeader));
      _userInfo = OTUser.fromJson(response.data);
    }
    return _userInfo;
  }

  // Migrated
  Future<bool?> isUserAdmin() async {
    return (await getUserProfile())!.is_admin;
  }

  // Migrated
  /// Non-async version of [isUserAdmin], will return false if data is not yet ready
  bool isUserAdminNonAsync() {
    return _userInfo?.is_admin ?? false;
  }

  // Migrated
  Future<List<int>> getFavoriteHoleId({bool forceUpdate = false}) async {
    return (await getUserProfile(forceUpdate: forceUpdate))!.favorites!;
  }

  // Migrated
  Future<List<OTHole>> getFavoriteHoles({
    int length = 10,
    int prefetchLength = 10,
  }) async {
    final Response response = await dio!.get(_BASE_URL + "/user/favorites",
        queryParameters: {"length": length, "prefetch_length": prefetchLength},
        options: Options(headers: _tokenHeader));
    final List result = response.data;
    return result.map((e) => OTHole.fromJson(e)).toList();
  }

  // Migrated
  Future<void> setFavorite(SetFavoriteMode mode, int? holeId) async {
    Response response;
    switch (mode) {
      case SetFavoriteMode.ADD:
        response = await dio!.post(_BASE_URL + "/user/favorites",
            data: {'hole_id': holeId}, options: Options(headers: _tokenHeader));
        break;
      case SetFavoriteMode.DELETE:
        response = await dio!.delete(_BASE_URL + "/user/favorites",
            data: {'hole_id': holeId}, options: Options(headers: _tokenHeader));
        break;
    }
    if (_userInfo?.favorites != null) {
      final Map<String, dynamic> result = response.data;
      _userInfo!.favorites = result["data"].cast<int>();
    }
  }

  /// Modify a post, requires Admin privilege
  /// Throws on failure.
  Future<void> adminModifyPost(
      String content, int? discussionId, int? postId) async {
    await dio!.post(_BASE_URL + "/admin/",
        data: {
          "content": content,
          "operation": "modify",
          "discussion_id": discussionId,
          "post_id": postId,
        },
        options: Options(headers: _tokenHeader));
  }

  /// Disable a post, requires Admin privilege
  /// Throws on failure.
  Future<void> adminDisablePost(int? discussionId, int? postId) async {
    await dio!.post(_BASE_URL + "/admin/",
        data: {
          "operation": "disable",
          "discussion_id": discussionId,
          "post_id": postId,
        },
        options: Options(headers: _tokenHeader));
  }

  /// Disable a discussion, requires Admin privilege
  /// Throws on failure.
  Future<void> adminDisableDiscussion(int? discussionId) async {
    await dio!.post(_BASE_URL + "/admin/",
        data: {
          "operation": "disable_discussion",
          "discussion_id": discussionId,
        },
        options: Options(headers: _tokenHeader));
  }

  /// Get sender username of a post, requires Admin privilege
  Future<String> adminGetUser(int? discussionId, int? postId) async {
    final response = await dio!.post(_BASE_URL + "/admin/",
        data: {
          "operation": "get_user",
          "discussion_id": discussionId,
          "post_id": postId,
        },
        options: Options(headers: _tokenHeader));
    return response.data.toString();
  }

  Future<List<Report>> adminGetReports(int page) async {
    final response = await dio!.get(_BASE_URL + "/admin/",
        queryParameters: {"page": page, "show_only_undealt": true},
        options: Options(headers: _tokenHeader));
    final result = response.data;
    return result.map<Report>((e) => Report.fromJson(e)).toList();
  }

  Future<String> adminSetReportDealt(int? reportId) async {
    final response = await dio!.post(_BASE_URL + "/admin/",
        data: {
          "operation": "set_report_dealed",
          "report_id": reportId,
        },
        options: Options(headers: _tokenHeader));
    return response.data.toString();
  }

  // Migrated
  /// Upload or update Push Notification token to server
  Future<void> updatePushNotificationToken(
      [String? token, String? id, PushNotificationServiceType? service]) async {
    if (isUserInitialized) {
      await dio!.post(_BASE_URL + "/users",
          data: {
            "service":
                (service ?? _pushNotificationService).toStringRepresentation(),
            "device_id": id ?? _deviceId,
            "token": token ?? _pushNotificationToken,
          },
          options: Options(headers: _tokenHeader));
    } else {
      _deviceId = id;
      _pushNotificationToken = token;
      _pushNotificationService = service;
    }
  }

  @override
  String get linkHost => "www.fduhole.com";
}

enum PushNotificationServiceType { APNS, MIPUSH }

extension StringRepresentation on PushNotificationServiceType? {
  String? toStringRepresentation() {
    switch (this) {
      case PushNotificationServiceType.APNS:
        return 'apns';
      case PushNotificationServiceType.MIPUSH:
        return 'mipush';
      case null:
        return null;
    }
  }
}

enum SetFavoriteMode { ADD, DELETE }

class NotLoginError implements FatalException {
  final String errorMessage;

  NotLoginError(this.errorMessage);
}

class LoginExpiredError implements Exception {}

class ImageUploadError implements Exception {}
