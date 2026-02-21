// ---------------------------------------------------------------------------
// AI Risk Analysis Data Model
// ---------------------------------------------------------------------------
class AiRiskAnalysis {
  final String riskLevel;
  final double riskScore;
  final String riskSummary;
  final List<String> primaryDrivers;
  final List<String> recommendedActions;

  AiRiskAnalysis({
    required this.riskLevel,
    required this.riskScore,
    required this.riskSummary,
    required this.primaryDrivers,
    required this.recommendedActions,
  });

  factory AiRiskAnalysis.fromJson(Map<String, dynamic> json) {
    return AiRiskAnalysis(
      riskLevel: json['risk_level'] as String,
      riskScore: (json['risk_score'] as num).toDouble(),
      riskSummary: json['explanation']['risk_summary'] as String,
      primaryDrivers: (json['explanation']['primary_drivers'] as List)
          .map((e) => e.toString())
          .toList(),
      recommendedActions:
          (json['recommendation']['recommended_actions'] as List)
              .map((e) => e.toString())
              .toList(),
    );
  }
}