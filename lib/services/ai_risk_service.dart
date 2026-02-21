import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_risk_analysis.dart';

// ---------------------------------------------------------------------------
// AI Risk Analysis API Service
// ---------------------------------------------------------------------------
class AiRiskService {
  static const String _baseUrl =
      'https://ai-road-risk-intelligence.onrender.com';

  /// Fetches AI-based accident risk analysis for a given [lat]/[lon].
  static Future<AiRiskAnalysis> fetchRiskAnalysis(
    double lat,
    double lon,
  ) async {
    final uri = Uri.parse('$_baseUrl/predict_location?lat=$lat&lon=$lon');

    final response = await http.post(uri).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      return AiRiskAnalysis.fromJson(jsonDecode(response.body));
    }

    throw Exception(
      'AI analysis request failed with status ${response.statusCode}',
    );
  }
}
