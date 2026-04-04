import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('https://crm.mb-scc.de/api/v1/App/user');
  final basicAuth = 'Basic ' + base64Encode(utf8.encode('janvonczapiewski:sandra1967'));
  try {
    final res = await http.get(url, headers: {'Authorization': basicAuth, 'Accept': 'application/json'});
    print('Status: ${res.statusCode}');
    print('Body: ${res.body.length > 100 ? res.body.substring(0, 100) : res.body}');
  } catch (e) {
    print('Ex: \$e');
  }
}
