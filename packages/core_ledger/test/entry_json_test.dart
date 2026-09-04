// Suite A — entry payload shape (02 §1.3) and unknown-field round-trip (03 §3.3.4, CLAUDE.md rule 6).
import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final book = TestBook('b1');
  final cash = book.cash('Cash');
  final kirana = book.expense('Kirana');

  test('serialises per 02 §1.3 wire names', () {
    final e = book.entry(
      [dr(kirana, rs(250)), cr(cash, rs(250))],
      id: 'e1',
      kind: EntryKind.moneyOut,
      date: d(2026, 5, 10),
      hlc: const Hlc(42),
      reviewRequired: true,
      reviewLimit: rs(100),
      reviewApprover: 'u9',
      note: 'atta',
    );
    final json = e.toJson();
    expect(json['id'], 'e1');
    expect(json['kind'], 'money_out');
    expect(json['status'], 'posted');
    expect(json['review_required'], true);
    expect(json['review_limit_paise'], 10000);
    expect(json['review_approver'], 'u9');
    expect(json['accounting_date'], '2026-05-10');
    expect(json['currency'], 'INR');
    expect(json['hlc'], 42);
    expect(json['lines'], [
      {'account_id': kirana.id, 'amount_paise': 25000},
      {'account_id': cash.id, 'amount_paise': -25000},
    ]);
    expect(json['created_by_user'], 'u1');
    expect(json['created_by_device'], 'd1');
    expect(json.containsKey('refs'), isFalse, reason: 'empty refs are omitted');
  });

  test('round-trips, preserving fields it does not understand', () {
    final wire = <String, Object?>{
      'id': 'e2',
      'book_id': 'b1',
      'kind': 'transfer',
      'status': 'posted',
      'review_required': false,
      'review_limit_paise': null,
      'accounting_date': '2026-06-01',
      'lines': [
        {
          'account_id': cash.id,
          'amount_paise': 100,
          'tag': 'share',
          'future_line_field': 1,
        },
        {'account_id': kirana.id, 'amount_paise': -100},
      ],
      'refs': {'transfer_group': 'g1', 'future_ref': 'x'},
      'created_by_user': 'u1',
      'created_by_device': 'd1',
      'hlc': 7,
      'attachment_ids': ['a1'],
      'channel': 'upi', // a newer client's field (02 §12 item 3) — must survive
      'future_object': {
        'nested': [1, 2, 3],
      },
    };
    final e = Entry.fromJson(wire);
    expect(e.kind, EntryKind.transfer);
    expect(e.refs.transferGroup, 'g1');
    expect(e.lines.first.tag, 'share');
    expect(e.attachmentIds, ['a1']);

    final amended = e.amendWith(newId: 'e3', hlc: const Hlc(8), note: 'fixed');
    final out = amended.toJson();
    expect(out['channel'], 'upi');
    expect(out['future_object'], {
      'nested': [1, 2, 3],
    });
    expect((out['refs'] as Map)['future_ref'], 'x');
    expect((out['refs'] as Map)['amends'], 'e2');
    expect(((out['lines'] as List).first as Map)['future_line_field'], 1);
    // Byte-stable: a second round trip changes nothing.
    expect(jsonEncode(Entry.fromJson(out).toJson()), jsonEncode(out));
  });

  test('rejects a non-integer amount (02 §1.4 rule 2)', () {
    final wire = <String, Object?>{
      'id': 'e4',
      'book_id': 'b1',
      'kind': 'money_in',
      'status': 'posted',
      'review_required': false,
      'accounting_date': '2026-06-01',
      'lines': [
        {'account_id': cash.id, 'amount_paise': 10.5},
        {'account_id': kirana.id, 'amount_paise': -10.5},
      ],
      'created_by_user': 'u1',
      'created_by_device': 'd1',
      'hlc': 7,
    };
    expect(() => Entry.fromJson(wire), throwsFormatException);
  });

  test('total is the sum of debits', () {
    final e = book.entry([
      dr(kirana, rs(300)),
      dr(cash, rs(200)),
      cr(cash, rs(500)),
    ]);
    expect(e.totalDebits, rs(500));
  });
}
