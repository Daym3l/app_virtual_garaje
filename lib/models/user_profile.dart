enum MembershipTier { free, premium, enterprise }

class UserProfile {
  const UserProfile({
    required this.id,
    required this.membership,
    required this.membershipStatus,
    this.membershipExpiresAt,
  });

  final String id;
  final MembershipTier membership;
  final String membershipStatus;
  final DateTime? membershipExpiresAt;

  bool get isPaidMember {
    if (membership == MembershipTier.free) return false;
    if (membershipStatus != 'active') return false;
    if (membershipExpiresAt == null) return true;
    return membershipExpiresAt!.isAfter(DateTime.now());
  }

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    return UserProfile(
      id: j['id'] as String,
      membership: _parseTier(j['membership'] as String? ?? 'free'),
      membershipStatus: j['membership_status'] as String? ?? 'active',
      membershipExpiresAt: j['membership_expires_at'] == null
          ? null
          : DateTime.parse(j['membership_expires_at'] as String),
    );
  }

  static MembershipTier _parseTier(String s) {
    switch (s.toLowerCase()) {
      case 'premium': return MembershipTier.premium;
      case 'enterprise': return MembershipTier.enterprise;
      default: return MembershipTier.free;
    }
  }
}
