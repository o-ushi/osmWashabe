/// JSST採点キャリブレーション（開発者モード専用）
///
/// 複数回の自己評価を EMA で蓄積し、アプリの評価傾向（甘め/辛め）を推定する。
/// bias > 0 → ユーザーがアプリより高く自己評価 → アプリは辛め（低く評価しがち）
/// bias < 0 → ユーザーがアプリより低く自己評価 → アプリは甘め（高く評価しがち）
abstract final class JsstCalibrationService {
  static const double _alpha = 0.3;

  /// JSST公式レベル（1-10）をアプリ内参照レベル（1-4）に変換
  static int jsstLevelToInternal(int jsstLevel) {
    if (jsstLevel <= 2) return 1;
    if (jsstLevel <= 4) return 2;
    if (jsstLevel <= 6) return 3;
    return 4;
  }

  /// アプリ内参照レベル（1-4）に対応するJSSTスライダー初期値
  static int internalToJsstDefault(int internal) {
    switch (internal) {
      case 1:
        return 1;
      case 2:
        return 3;
      case 3:
        return 5;
      default:
        return 8;
    }
  }

  /// EMAでバイアスを更新する
  static double updateBias({
    required double currentBias,
    required int userInternalLevel,
    required int appInternalLevel,
  }) {
    final correction = (userInternalLevel - appInternalLevel).toDouble();
    return _alpha * correction + (1 - _alpha) * currentBias;
  }

  /// バイアスを適用した補正後レベル（1-4にクランプ）
  static int? adjustedLevel(int? appLevel, double bias) {
    if (appLevel == null) return null;
    return (appLevel + bias).round().clamp(1, 4);
  }

  /// 評価傾向ラベル（アプリの評価がどちらに偏っているか）
  static String biasLabel(double bias) {
    if (bias.abs() < 0.15) return '標準';
    return bias > 0 ? '辛め' : '甘め';
  }
}
