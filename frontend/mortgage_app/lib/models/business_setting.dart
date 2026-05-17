class BusinessSetting {
  final int id;
  final bool strictMode;
  final int gracePeriodDays;
  final bool fiveDayLogic;

  BusinessSetting({
    required this.id,
    required this.strictMode,
    required this.gracePeriodDays,
    required this.fiveDayLogic,
  });

  factory BusinessSetting.fromJson(Map<String, dynamic> json) {
    return BusinessSetting(
      id: json['id'],
      strictMode: json['strict_mode'] ?? false,
      gracePeriodDays: json['grace_period_days'] ?? 5,
      fiveDayLogic: json['five_day_logic'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'strict_mode': strictMode,
      'grace_period_days': gracePeriodDays,
      'five_day_logic': fiveDayLogic,
    };
  }
}
