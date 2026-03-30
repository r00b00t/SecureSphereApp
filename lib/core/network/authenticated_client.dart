import 'package:http/http.dart' as http;
import 'package:get/get.dart';
import 'package:decvault/features/auth/services/auth_service.dart';

/// An [http.BaseClient] that automatically handles 401 Unauthorized responses
/// on JWT-authenticated requests.
///
/// When a request carrying `Authorization: Bearer …` receives a 401, this
/// client calls [AuthService.handleUnauthorized] in a fire-and-forget
/// microtask: the stored JWT is cleared and the user is routed to /auth.
///
/// Requests using `Authorization: Basic …` (direct SIA / renterd node calls)
/// are passed through completely unchanged — a wrong SIA password should never
/// log the user out of the app.
class AuthenticatedClient extends http.BaseClient {
  final http.Client _inner;

  AuthenticatedClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);

    if (response.statusCode == 401 && _isBearerRequest(request)) {
      // Fire-and-forget: return the response to the caller immediately so it
      // can handle the 401 itself (e.g. show a specific error), while the
      // logout flow runs asynchronously in the background.
      Future.microtask(() async {
        try {
          await Get.find<AuthService>().handleUnauthorized();
        } catch (_) {}
      });
    }

    return response;
  }

  bool _isBearerRequest(http.BaseRequest request) {
    final auth = request.headers['Authorization'] ?? '';
    return auth.startsWith('Bearer ');
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
