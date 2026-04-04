import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('CORS Proxy running on localhost:8080');
  
  await for (HttpRequest request in server) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers',
        'Authorization, Content-Type, Accept, X-Api-Key, X-Auth-Token, X-Hmac-Data');
    request.response.headers.add('Access-Control-Expose-Headers', '*');
    
    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      continue;
    }
    
    final path = request.uri.path == '' ? '/' : request.uri.path;
    final query = request.uri.hasQuery ? '?${request.uri.query}' : '';
    final targetUrl = Uri.parse('https://crm.mb-scc.de$path$query');
    
    final reqBytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final clientRequest = http.Request(request.method, targetUrl);
    clientRequest.bodyBytes = reqBytes;
    
    request.headers.forEach((name, values) {
      if (name.toLowerCase() != 'host' && name.toLowerCase() != 'origin' && name.toLowerCase() != 'cookie') {
        clientRequest.headers[name] = values.join(', ');
      }
    });

    try {
      final response = await http.Client().send(clientRequest);
      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, value) {
        if (name.toLowerCase() != 'access-control-allow-origin' && name.toLowerCase() != 'transfer-encoding' && name.toLowerCase() != 'content-encoding') {
          request.response.headers.set(name, value);
        }
      });
      await response.stream.pipe(request.response);
    } catch (e) {
      print('Proxy error: $e');
      request.response.statusCode = 500;
      await request.response.close();
    }
  }
}
