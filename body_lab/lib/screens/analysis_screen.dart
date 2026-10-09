import 'package:flutter/material.dart';

import '../analysis/daily_dataset.dart';
import '../data/phase_repository.dart';
import '../data/profile_repository.dart';
import 'combo_screen.dart';
import 'phases_screen.dart';

/// 分析頁：實驗階段 / 組合分析熱力圖。
class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({
    super.key,
    required this.phases,
    required this.dataset,
    required this.profile,
    this.bottomBanner,
  });

  final PhaseRepository phases;
  final DatasetRepository dataset;
  final ProfileRepository profile;

  /// 固定在頁面底部的橫幅（廣告）；測試不傳就不顯示。
  final Widget? bottomBanner;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分析'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '實驗階段'),
              Tab(text: '組合分析'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PhasesScreen(phases: phases, dataset: dataset, profile: profile),
            ComboScreen(dataset: dataset, profile: profile),
          ],
        ),
        bottomNavigationBar: bottomBanner,
      ),
    );
  }
}
