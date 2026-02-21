import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/ai_risk_analysis.dart';

// ---------------------------------------------------------------------------
// AiRiskSheet  – displays the AI risk analysis result
// ---------------------------------------------------------------------------
class AiRiskSheet extends StatelessWidget {
  final LatLng location;
  final AiRiskAnalysis analysis;

  const AiRiskSheet({super.key, required this.location, required this.analysis});

  Color get _riskColor {
    switch (analysis.riskLevel.toLowerCase()) {
      case 'high':
        return const Color(0xFFE53935);
      case 'medium':
        return const Color(0xFFFB8C00);
      case 'low':
        return const Color(0xFF43A047);
      default:
        return const Color(0xFF1E88E5);
    }
  }

  IconData get _riskIcon {
    switch (analysis.riskLevel.toLowerCase()) {
      case 'high':
        return Icons.dangerous_rounded;
      case 'medium':
        return Icons.warning_amber_rounded;
      case 'low':
        return Icons.check_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 600;
    final scorePercent = (analysis.riskScore * 100).toStringAsFixed(1);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1923),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          isTablet ? 32 : 20,
          16,
          isTablet ? 32 : 20,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header row with AI badge + coordinates
            Row(
              children: [
                _AiBadge(),
                const Spacer(),
                Text(
                  '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Risk level card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _riskColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: _riskColor.withOpacity(0.3), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _riskColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_riskIcon, color: _riskColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${analysis.riskLevel} Risk',
                          style: TextStyle(
                            color: _riskColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Risk Score: $scorePercent%',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  // Score ring
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: analysis.riskScore,
                          strokeWidth: 5,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(_riskColor),
                        ),
                        Text(
                          '$scorePercent%',
                          style: TextStyle(
                            color: _riskColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Risk Summary
            const _SectionLabel(label: 'Risk Summary'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                analysis.riskSummary,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13.5, height: 1.65),
              ),
            ),

            const SizedBox(height: 20),

            // Primary Risk Drivers
            const _SectionLabel(label: 'Primary Risk Drivers'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: analysis.primaryDrivers.map((driver) {
                return _DriverChip(label: driver.replaceAll('_', ' '));
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Recommended Actions
            const _SectionLabel(label: 'Recommended Actions'),
            const SizedBox(height: 10),
            ...analysis.recommendedActions.asMap().entries.map((entry) {
              return _ActionTile(index: entry.key, action: entry.value);
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AiLoadingSheet  – shown while the API call is in-flight
// ---------------------------------------------------------------------------
class AiLoadingSheet extends StatefulWidget {
  final LatLng location;
  const AiLoadingSheet({super.key, required this.location});

  @override
  State<AiLoadingSheet> createState() => _AiLoadingSheetState();
}

class _AiLoadingSheetState extends State<AiLoadingSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F1923),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 16, 24, MediaQuery.of(context).padding.bottom + 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 32),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          RotationTransition(
            turns: _controller,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFF6C63FF),
                    Color(0xFF3B82F6),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.auto_awesome, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Analyzing Location',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.location.latitude.toStringAsFixed(4)}, ${widget.location.longitude.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI is computing accident risk factors…',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable sub-widgets
// ---------------------------------------------------------------------------
class _AiBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text(
            'AI Analysis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _DriverChip extends StatelessWidget {
  final String label;
  const _DriverChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withOpacity(0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.trending_up_rounded,
              color: Color(0xFF9B8BFF), size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFBEB5FF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final int index;
  final String action;
  const _ActionTile({required this.index, required this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF6C63FF)]),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              action,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}