// The FICTIONAL demo roster — what a debug build uses when no
// `RF_DEMO_ROSTER` define was passed, and what every test builds from.
//
// Every name here is invented; no real person is described. The numbers sit in
// the dev-only `+91 5…` range (`phone_shape.dart`: no real Indian mobile begins
// with 5), in case blocks 81–83 so they never coincide with the owner's real
// roster. A release build never reaches this constant (`demo_gate.dart`).
//
// The three cases cover what the builder must get right:
// * Sharma — a joint family: three heads, equal / unequal / outside-partner
//   businesses, sub-family books, and one business Rakesh is only a *member*
//   of (which must not be built for him);
// * Kaur — one person, a personal book and a business with an operator;
// * Verma — a trust with a secretary and a treasurer.
import 'demo_roster.dart';

const fictionalDemoRoster = DemoRoster([
  DemoCase(
    people: [
      DemoPerson(
        key: 'rakesh',
        name: 'Rakesh Sharma',
        phone: '+91 5000 081 001',
      ),
      DemoPerson(
        key: 'mukesh',
        name: 'Mukesh Sharma',
        phone: '+91 5000 081 002',
      ),
      DemoPerson(
        key: 'suresh',
        name: 'Suresh Sharma',
        phone: '+91 5000 081 003',
      ),
      DemoPerson(
        key: 'sunita',
        name: 'Sunita Sharma',
        phone: '+91 5000 081 004',
      ),
      DemoPerson(key: 'neha', name: 'Neha Sharma', phone: '+91 5000 081 005'),
      // Partner in the kiln only, not on the app.
      DemoPerson(key: 'anil', name: 'Anil Gupta', phone: '+91 5000 081 006'),
    ],
    books: [
      DemoBook(
        key: 'sharma.joint',
        name: 'Sharma Joint Family',
        kind: DemoBookKind.joint,
        roles: {
          'rakesh': DemoRole.head,
          'mukesh': DemoRole.head,
          'suresh': DemoRole.head,
        },
      ),
      DemoBook(
        key: 'sharma.dairy',
        name: 'Sharma Dairy',
        kind: DemoBookKind.business,
        shares: [('rakesh', '1/3'), ('mukesh', '1/3'), ('suresh', '1/3')],
        roles: {
          'rakesh': DemoRole.admin,
          'mukesh': DemoRole.admin,
          'suresh': DemoRole.admin,
        },
      ),
      DemoBook(
        key: 'sharma.farm',
        name: 'Sharma Farm',
        kind: DemoBookKind.business,
        shares: [('rakesh', '50%'), ('mukesh', '30%'), ('suresh', '20%')],
        roles: {
          'rakesh': DemoRole.admin,
          'mukesh': DemoRole.member,
          'suresh': DemoRole.member,
        },
      ),
      DemoBook(
        key: 'sharma.kiln',
        name: 'Sharma Brick Kiln',
        kind: DemoBookKind.business,
        shares: [
          ('rakesh', '25%'),
          ('mukesh', '25%'),
          ('suresh', '25%'),
          ('anil', '25%'),
        ],
        roles: {
          'rakesh': DemoRole.admin,
          'mukesh': DemoRole.admin,
          'suresh': DemoRole.admin,
        },
      ),
      DemoBook(
        key: 'sharma.transport',
        name: 'Sharma Transport',
        kind: DemoBookKind.business,
        shares: [('mukesh', '50%'), ('suresh', '50%')],
        roles: {
          'mukesh': DemoRole.admin,
          'suresh': DemoRole.admin,
          'rakesh': DemoRole.member,
        },
      ),
      DemoBook(
        key: 'sharma.sub.rakesh',
        name: "Rakesh's Household",
        kind: DemoBookKind.family,
        roles: {'rakesh': DemoRole.head, 'sunita': DemoRole.member},
      ),
      DemoBook(
        key: 'sharma.sub.mukesh',
        name: "Mukesh's Household",
        kind: DemoBookKind.family,
        roles: {'mukesh': DemoRole.head},
      ),
      DemoBook(
        key: 'sharma.sub.suresh',
        name: "Suresh's Household",
        kind: DemoBookKind.family,
        roles: {'suresh': DemoRole.head, 'neha': DemoRole.viewer},
      ),
    ],
    personalBooksFor: ['rakesh', 'mukesh', 'suresh', 'sunita'],
  ),
  DemoCase(
    people: [
      DemoPerson(key: 'simran', name: 'Simran Kaur', phone: '+91 5000 082 001'),
      DemoPerson(key: 'ravi', name: 'Ravi Kumar', phone: '+91 5000 082 002'),
    ],
    books: [
      DemoBook(
        key: 'kaur.personal',
        name: 'Simran Kaur',
        kind: DemoBookKind.personal,
        roles: {'simran': DemoRole.admin},
      ),
      DemoBook(
        key: 'kaur.boutique',
        name: 'Kaur Boutique',
        kind: DemoBookKind.business,
        roles: {'simran': DemoRole.admin, 'ravi': DemoRole.operator},
      ),
    ],
  ),
  DemoCase(
    people: [
      DemoPerson(key: 'vijay', name: 'Vijay Verma', phone: '+91 5000 083 001'),
      DemoPerson(
        key: 'deepak',
        name: 'Deepak Verma',
        phone: '+91 5000 083 002',
      ),
    ],
    books: [
      DemoBook(
        key: 'verma.trust',
        name: 'Verma Seva Trust',
        kind: DemoBookKind.organization,
        roles: {'vijay': DemoRole.admin, 'deepak': DemoRole.operator},
      ),
    ],
  ),
]);
