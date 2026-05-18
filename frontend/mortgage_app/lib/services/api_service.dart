import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/party.dart';
import '../models/entry.dart';
import '../models/jewellery_item.dart';
import '../models/business_setting.dart';
import 'settings_service.dart';

class ApiService {
  static String get baseUrl => SettingsService.apiBaseUrl;

  Map<String, String> get _headers {
    final token = SettingsService.token;
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }
    return headers;
  }

  // ─── Business Settings ──────────────────────────────────────
  Future<BusinessSetting> fetchBusinessSettings() async {
    final response = await http.get(Uri.parse('$baseUrl/settings/'), headers: _headers);
    if (response.statusCode == 200) {
      return BusinessSetting.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to load business settings');
  }

  Future<void> updateBusinessSettings(BusinessSetting setting) async {
    final response = await http.put(
      Uri.parse('$baseUrl/settings/'),
      headers: _headers,
      body: jsonEncode(setting.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update business settings');
    }
  }

  // ─── Parties ───────────────────────────────────────────────
  Future<List<Party>> fetchParties({String? search}) async {
    final uri = Uri.parse('$baseUrl/parties/${search != null ? '?search=$search' : ''}');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map((e) => Party.fromJson(e)).toList();
    }
    throw Exception('Failed to load parties');
  }

  Future<void> createParty({
    required String name,
    required String phone,
    required String address,
    String note = '',
    String? defaultInterestRate,
  }) async {
    final Map<String, dynamic> body = {
      'name': name,
      'phone': phone,
      'address': address,
      'note': note,
    };
    if (defaultInterestRate != null && defaultInterestRate.isNotEmpty) {
      body['default_interest_rate'] = defaultInterestRate;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/parties/'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 201) throw Exception('Failed to create party');
  }

  Future<Party> createPartyAndReturn({
    required String name,
    required String phone,
    required String address,
    String note = '',
    String? defaultInterestRate,
  }) async {
    final Map<String, dynamic> body = {'name': name, 'phone': phone, 'address': address, 'note': note};
    if (defaultInterestRate != null && defaultInterestRate.isNotEmpty) {
      body['default_interest_rate'] = defaultInterestRate;
    }
    final response = await http.post(
      Uri.parse('$baseUrl/parties/'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) {
      return Party.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create party: ${response.body}');
  }

  Future<void> deleteParty(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/parties/$id/'), headers: _headers);
    if (response.statusCode != 204) throw Exception('Failed to delete party');
  }

  // ─── Entries ───────────────────────────────────────────────
  Future<List<Entry>> fetchEntries(int partyId) async {
    final response = await http.get(Uri.parse('$baseUrl/entries/?party=$partyId'), headers: _headers);
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map((e) => Entry.fromJson(e)).toList();
    }
    throw Exception('Failed to load entries');
  }

  Future<List<Entry>> fetchAllEntries({String? search, String? status}) async {
    String query = '';
    if (search != null && search.isNotEmpty) query += 'search=$search&';
    if (status != null && status.isNotEmpty) query += 'status=$status&';
    final response = await http.get(Uri.parse('$baseUrl/entries/?$query'), headers: _headers);
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map((e) => Entry.fromJson(e)).toList();
    }
    throw Exception('Failed to load entries');
  }

  Future<void> createEntry({
    required int party,
    required String amount,
    required String interest,
    String note = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/entries/'),
      headers: _headers,
      body: jsonEncode({'party': party, 'amount': amount, 'interest': interest, 'note': note}),
    );
    if (response.statusCode != 201) throw Exception('Failed to create entry');
  }

  Future<Entry> createEntryAndReturn({
    required int party,
    required String amount,
    required String interest,
    String note = '',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/entries/'),
      headers: _headers,
      body: jsonEncode({'party': party, 'amount': amount, 'interest': interest, 'note': note}),
    );
    if (response.statusCode == 201) {
      return Entry.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create entry: ${response.body}');
  }

  Future<void> updateEntry(int id, {
    String? amount,
    String? interest,
    String? note,
    String? status,
  }) async {
    final Map<String, dynamic> body = {};
    if (amount != null) body['amount'] = amount;
    if (interest != null) body['interest'] = interest;
    if (note != null) body['note'] = note;
    if (status != null) body['status'] = status;

    final response = await http.patch(
      Uri.parse('$baseUrl/entries/$id/'),
      headers: _headers,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) throw Exception('Failed to update entry');
  }

  Future<void> deleteEntry(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/entries/$id/'), headers: _headers);
    if (response.statusCode != 204) throw Exception('Failed to delete entry');
  }

  Future<Entry> withdrawEntry(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/entries/$id/withdraw/'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return Entry.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Withdraw failed');
  }

  Future<Entry> markOverdue(int id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/entries/$id/mark_overdue/'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return Entry.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to mark overdue');
  }

  Future<Map<String, dynamic>> fetchStats() async {
    final response = await http.get(Uri.parse('$baseUrl/entries/stats/'), headers: _headers);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load stats');
  }

  // ─── Items ─────────────────────────────────────────────────
  Future<List<JewelleryItem>> fetchItems(int entryId) async {
    final response = await http.get(Uri.parse('$baseUrl/items/?entry=$entryId'), headers: _headers);
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map((e) => JewelleryItem.fromJson(e)).toList();
    }
    throw Exception('Failed to load items');
  }

  Future<JewelleryItem> createItem({
    required int entry,
    required String itemType,
    required String name,
    required String weight,
    String note = '',
    String? imagePath,
  }) async {
    final uri = Uri.parse('$baseUrl/items/');
    final request = http.MultipartRequest('POST', uri);
    
    // Add auth header to multipart
    final token = SettingsService.token;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }
    
    request.fields['entry'] = entry.toString();
    request.fields['item_type'] = itemType;
    request.fields['name'] = name;
    request.fields['note'] = note;
    
    if (weight.isNotEmpty) {
      request.fields['weight'] = weight;
    }
    
    if (imagePath != null && imagePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath('image', imagePath));
    }
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201) {
      return JewelleryItem.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Item create failed (${response.statusCode}): ${response.body}');
    }
  }

  Future<void> deleteItem(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/items/$id/'), headers: _headers);
    if (response.statusCode != 204) throw Exception('Failed to delete item');
  }
}
