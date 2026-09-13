// The 01 §2 designation tables, as suggestions for S9.1 (07 §12: "picked from
// the 01 §2 tables for the tenant type, or typed free").
//
// A designation is a **display label** and never a permission (06 §1.0 🔒
// Option B) — nothing in this file is ever consulted by a capability check.
// Where the owner's table offers two forms, the **first** is the label and
// the second stays a search synonym (01 §2 🔒), so only the first is minted
// as a string here.
//
// ⚠️ SPEC: 01 §2 publishes two tables — *Trust / organization* and
// *Business*. It publishes none for a **family** tenant, and 06 §1.0's
// "Family / business default" column lists the five stored *roles*, not
// designations. Rather than invent a family list, S9.1 suggests nothing for a
// family and offers only the free-text field (`invite.designation.no_table`).
import '../../l10n/gen/app_localizations.dart';
import 'members_repository.dart';

/// One suggested label. The enum exists so the picker never passes a
/// translated string around as an identity.
enum Designation {
  // Trust / organization (01 §2).
  president,
  vicePresident,
  chairman,
  secretary,
  jointSecretary,
  treasurer,
  trustee,
  managingTrustee,
  founder,
  patron,
  executiveMember,
  auditor,
  // Business (01 §2).
  owner,
  partner,
  director,
  managingDirector,
  ceo,
  generalManager,
  manager,
  assistantManager,
  accountant,
  salesExecutive,
  employee,
  advisor,
}

/// The 01 §2 trust / organization table, in the document's own order.
const organizationDesignations = [
  Designation.president,
  Designation.vicePresident,
  Designation.chairman,
  Designation.secretary,
  Designation.jointSecretary,
  Designation.treasurer,
  Designation.trustee,
  Designation.managingTrustee,
  Designation.founder,
  Designation.patron,
  Designation.executiveMember,
  Designation.auditor,
];

/// The 01 §2 business table, in the document's own order.
const businessDesignations = [
  Designation.owner,
  Designation.partner,
  Designation.director,
  Designation.managingDirector,
  Designation.ceo,
  Designation.generalManager,
  Designation.manager,
  Designation.assistantManager,
  Designation.accountant,
  Designation.salesExecutive,
  Designation.employee,
  Designation.advisor,
];

/// What S9.1 suggests for [type]. Empty for a family — see the file header.
List<Designation> designationsFor(TenantType type) => switch (type) {
  TenantType.organization => organizationDesignations,
  TenantType.businessGroup => businessDesignations,
  TenantType.family => const [],
};

/// The label for [d] in the reader's own language (01 §2, all three columns).
String designationLabel(AppLocalizations l, Designation d) => switch (d) {
  Designation.president => l.inviteDesignationPresident,
  Designation.vicePresident => l.inviteDesignationVicePresident,
  Designation.chairman => l.inviteDesignationChairman,
  Designation.secretary => l.inviteDesignationSecretary,
  Designation.jointSecretary => l.inviteDesignationJointSecretary,
  Designation.treasurer => l.inviteDesignationTreasurer,
  Designation.trustee => l.inviteDesignationTrustee,
  Designation.managingTrustee => l.inviteDesignationManagingTrustee,
  Designation.founder => l.inviteDesignationFounder,
  Designation.patron => l.inviteDesignationPatron,
  Designation.executiveMember => l.inviteDesignationExecutiveMember,
  Designation.auditor => l.inviteDesignationAuditor,
  Designation.owner => l.inviteDesignationOwner,
  Designation.partner => l.inviteDesignationPartner,
  Designation.director => l.inviteDesignationDirector,
  Designation.managingDirector => l.inviteDesignationManagingDirector,
  Designation.ceo => l.inviteDesignationCeo,
  Designation.generalManager => l.inviteDesignationGeneralManager,
  Designation.manager => l.inviteDesignationManager,
  Designation.assistantManager => l.inviteDesignationAssistantManager,
  Designation.accountant => l.inviteDesignationAccountant,
  Designation.salesExecutive => l.inviteDesignationSalesExecutive,
  Designation.employee => l.inviteDesignationEmployee,
  Designation.advisor => l.inviteDesignationAdvisor,
};

/// The stored role's own name (06 §1.1) — a capability word, never a
/// designation.
String roleLabel(AppLocalizations l, BookRole role) => switch (role) {
  BookRole.admin => l.membersRoleAdmin,
  BookRole.head => l.membersRoleHead,
  BookRole.member => l.membersRoleMember,
  BookRole.operator => l.membersRoleOperator,
  BookRole.viewer => l.membersRoleViewer,
};

/// What that role may do, in plain words — always shown beside a designation
/// so a grand title never implies powers it does not carry (13 §2.4 🔒).
String rolePlainWords(AppLocalizations l, BookRole role) => switch (role) {
  BookRole.admin => l.membersRoleAdminPlain,
  BookRole.head => l.membersRoleHeadPlain,
  BookRole.member => l.membersRoleMemberPlain,
  BookRole.operator => l.membersRoleOperatorPlain,
  BookRole.viewer => l.membersRoleViewerPlain,
};
