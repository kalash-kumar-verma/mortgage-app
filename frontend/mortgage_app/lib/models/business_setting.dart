class BusinessSetting {
  final int? id;
  final bool strictMode;
  final int gracePeriodDays;
  final bool fiveDayLogic;
  final String? updatedAt;

  BusinessSetting({
    this.id,
    this.strictMode = false,
    this.gracePeriodDays = 5,
    this.fiveDayLogic = false,
    this.updatedAt,
  });

  factory BusinessSetting.fromJson(Map<String, dynamic> json) {
    return BusinessSetting(
      id: json['id'],
      strictMode: json['strict_mode'] ?? false,
      gracePeriodDays: json['grace_period_days'] ?? 5,
      fiveDayLogic: json['five_day_logic'] ?? false,
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'strict_mode': strictMode,
      'grace_period_days': gracePeriodDays,
      'five_day_logic': fiveDayLogic,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}
