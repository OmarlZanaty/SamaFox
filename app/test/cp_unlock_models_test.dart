import 'package:flutter_test/flutter_test.dart';
import 'package:samafox/repositories/cp_repository.dart';
import 'package:samafox/widgets/cp_relationship.dart';

// صلاحيات فتح CP (2026-09-22) — the app side reads what the server decides.
void main() {
  group('CpUnlockStatus', () {
    test('free policy needs no payment', () {
      final s = CpUnlockStatus.fromJson({'unlocked': false, 'mode': 'free', 'feeCoins': 0, 'balance': 40, 'shortfall': 0});
      expect(s.needsPayment, isFalse);
    });

    test('fee policy, not unlocked: needs payment and carries the shortfall', () {
      final s = CpUnlockStatus.fromJson({'unlocked': false, 'mode': 'fee', 'feeCoins': 300, 'balance': 40, 'shortfall': 260});
      expect(s.needsPayment, isTrue);
      expect(s.feeCoins, 300);
      expect(s.shortfall, 260);
    });

    test('already unlocked never needs payment', () {
      final s = CpUnlockStatus.fromJson({'unlocked': true, 'mode': 'fee', 'feeCoins': 0, 'balance': 0, 'shortfall': 0});
      expect(s.needsPayment, isFalse);
    });
  });

  group('CpException numbers', () {
    test('INSUFFICIENT_COINS exposes fee, balance and shortfall', () {
      final e = CpException('رصيدك لا يكفي', code: 'INSUFFICIENT_COINS', status: 402, data: {
        'success': false,
        'code': 'INSUFFICIENT_COINS',
        'feeCoins': 300,
        'balance': 40,
        'shortfall': 260,
      });
      expect(e.feeCoins, 300);
      expect(e.balance, 40);
      expect(e.shortfall, 260);
    });

    test('no body means no numbers', () {
      expect(CpException('x').shortfall, isNull);
    });
  });

  group('CpPartner server level', () {
    Map<String, dynamic> row({Object? level, Object? featured, int partnerId = 9}) => {
          'pairId': 3,
          'partner': {'id': partnerId, 'name': 'Sara', 'level': 42},
          'createdAt': '2026-08-01T10:00:00Z',
          if (level != null) 'level': level,
          if (level != null) 'levelName': 'حب كبير',
          if (level != null) 'cpValue': 1200,
          if (level != null) 'days': 53,
          if (featured != null) 'featured': featured,
        };

    test('pair level is read separately from the partner user LV', () {
      final p = CpPartner.fromJson(row(level: 3));
      expect(p.cpLevel, 3);
      expect(p.cpLevelName, 'حب كبير');
      expect(p.cpValue, 1200);
      expect(p.cpDays, 53);
      expect(p.level, 42); // the partner's own LV, untouched
    });

    test('an older server leaves the CP fields null', () {
      final p = CpPartner.fromJson(row());
      expect(p.cpLevel, isNull);
      expect(p.featured, isNull);
    });

    test('tier colours clamp beyond the table', () {
      expect(CpTier.forLevel(0).level, 1);
      expect(CpTier.forLevel(3).level, 3);
      expect(CpTier.forLevel(12).level, CpTier.all.length);
    });
  });

  group('CpSendResult (هدايا CP)', () {
    test('a CP gift to a partner carries the points, the level and the balance', () {
      final r = CpSendResult.fromJson({
        'kind': 'partner_gift',
        'pointsAdded': 500,
        'cpValue': 1500,
        'level': 3,
        'levelName': 'حب كبير',
        'leveledUp': true,
        'balance': 900,
      });
      expect(r.isPartnerGift, isTrue);
      expect(r.pointsAdded, 500);
      expect(r.level, 3);
      expect(r.leveledUp, isTrue);
      expect(r.balance, 900);
    });

    test('an invitation (or an older server with no kind) is not a partner gift', () {
      expect(CpSendResult.fromJson({'kind': 'invitation', 'id': 7}).isPartnerGift, isFalse);
      expect(CpSendResult.fromJson({'id': 7}).isPartnerGift, isFalse);
    });
  });

  group('CpFeatured.pick', () {
    CpPartner p(int id, {bool? featured}) => CpPartner(pairId: id, userId: id, name: 'u$id', featured: featured);

    test("the server's featured flag wins over the device choice", () {
      final list = [p(1, featured: false), p(2, featured: true), p(3, featured: false)];
      expect(CpFeatured.pick(list, 3)!.userId, 2);
    });

    test('older server: device choice, then newest', () {
      final list = [p(1), p(2), p(3)];
      expect(CpFeatured.pick(list, 3)!.userId, 3);
      expect(CpFeatured.pick(list, 99)!.userId, 1);
      expect(CpFeatured.pick(const [], 1), isNull);
    });
  });
}
