import 'package:flutter/material.dart';

import '../repositories/cp_repository.dart';

/// صلاحيات فتح CP (2026-09-22) — the step before a CP invitation goes out.
///
/// The admin may make opening CP cost coins (for everyone, or for one user).
/// The rule the client set: the user sees the fee BEFORE anything is taken,
/// and only after "موافق" does the server deduct it — atomically, once. If the
/// balance is short, the user is told by how much and nothing moves.
///
/// Under the default policy (free) this is a single status call and no dialog,
/// so nothing changes for anyone until the admin decides.
///
/// The server enforces all of this on `POST /cp/requests` regardless (403
/// CP_LOCKED), so a failure to fetch the quote here just lets the request go
/// and the caller handles CP_LOCKED by running the gate again.
class CpUnlockGate {
  CpUnlockGate._();

  static const _kPink = Color(0xFFFF4081);
  static const _kGold = Color(0xFFF5C242);
  static const _kCard = Color(0xFF1A0E3E);

  static Future<CpGateResult> ensure(BuildContext context, {CpRepository? repository}) async {
    final repo = repository ?? CpRepository();

    final CpUnlockStatus status;
    try {
      status = await repo.unlockStatus();
    } on CpException {
      // Older server without the endpoint, or a blip: let the send decide.
      return const CpGateResult.proceed();
    }
    if (!status.needsPayment) return const CpGateResult.proceed();
    if (!context.mounted) return const CpGateResult.stop();

    final agreed = await _showQuote(context, status);
    if (agreed != true) return const CpGateResult.stop();

    try {
      final result = await repo.confirmUnlock();
      return CpGateResult.proceed(
        balance: result.balance,
        message: result.paidCoins > 0 ? 'تم فتح الـ CP — تم خصم ${result.paidCoins} كوينز' : null,
      );
    } on CpException catch (e) {
      if (e.code == 'INSUFFICIENT_COINS') {
        return CpGateResult.stop(message: insufficientMessage(e.shortfall), error: true);
      }
      return CpGateResult.stop(message: e.message, error: true);
    }
  }

  /// "رصيدك لا يكفي" with the missing amount when the server sent it.
  static String insufficientMessage(int? shortfall) => shortfall != null && shortfall > 0
      ? 'رصيدك لا يكفي لفتح الـ CP — ينقصك $shortfall كوينز'
      : 'رصيدك لا يكفي لفتح الـ CP';

  static Future<bool?> _showQuote(BuildContext context, CpUnlockStatus s) {
    final short = s.shortfall > 0;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _kCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _kPink.withOpacity(0.5)),
          ),
          title: const Row(
            children: [
              Text('💞', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Text('فتح الـ CP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'لازم تفتح الـ CP قبل ما تبعت أول دعوة. الرسوم بتتدفع مرة واحدة بس.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
              const SizedBox(height: 14),
              _line('الرسوم', '${s.feeCoins} كوينز', color: _kGold),
              const SizedBox(height: 6),
              _line('رصيدك', '${s.balance} كوينز'),
              if (short) ...[
                const SizedBox(height: 12),
                Text(
                  insufficientMessage(s.shortfall),
                  style: TextStyle(color: Colors.red[300], fontWeight: FontWeight.bold, height: 1.4),
                ),
              ],
            ],
          ),
          actions: short
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('حسناً', style: TextStyle(color: Colors.white70)),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'موافق — ادفع ${s.feeCoins}',
                      style: const TextStyle(color: _kPink, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  static Widget _line(String label, String value, {Color color = Colors.white}) => Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          const Spacer(),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      );
}

/// What [CpUnlockGate.ensure] decided.
class CpGateResult {
  /// Send the invitation.
  final bool proceed;

  /// The balance after a paid unlock — authoritative, show it.
  final int? balance;

  /// Something to tell the user (a receipt, or why it stopped).
  final String? message;
  final bool error;

  const CpGateResult.proceed({this.balance, this.message})
      : proceed = true,
        error = false;

  const CpGateResult.stop({this.message, this.error = false})
      : proceed = false,
        balance = null;
}
