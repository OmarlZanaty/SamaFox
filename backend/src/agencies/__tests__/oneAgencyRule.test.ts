import test from 'node:test';
import assert from 'node:assert/strict';
import { findBlockingMembership, ALREADY_IN_AGENCY_MESSAGE } from '../oneAgencyRule';

type Role = 'OWNER' | 'BRANCH' | 'MEMBER';
type Seat = {
  id: number; agencyId: number; userId: number; role: Role;
  agency: { id: number; agencyName: string; type: 'HOSTING' | 'CHARGING' };
};
const seat = (role: Role, type: 'HOSTING' | 'CHARGING', agencyId = 1): Seat => ({
  id: 100, agencyId, userId: 10, role,
  agency: { id: agencyId, agencyName: 'Agency', type },
});
const fakeTx = (members: Seat[]) => ({
  agencyMember: {
    findFirst: async ({ where, include }: any) => {
      // No type/status filter: every other agency's seat must count.
      assert.deepEqual(Object.keys(where).sort(), ['agencyId', 'role', 'userId']);
      assert.deepEqual(include, { agency: { select: { id: true, agencyName: true, type: true } } });
      return members.find(m => m.userId === where.userId &&
        m.agencyId !== where.agencyId.not && where.role.in.includes(m.role)) ?? null;
    },
  },
});

for (const type of ['HOSTING', 'CHARGING'] as const) {
  for (const existingRole of ['MEMBER', 'BRANCH', 'OWNER'] as const) {
    for (const newRole of ['MEMBER', 'BRANCH'] as const) {
      test(`${type} ${existingRole} elsewhere blocks ${newRole}`, async () => {
        const existing = seat(existingRole, type);
        assert.deepEqual(await findBlockingMembership(fakeTx([existing]), 10, 2, newRole), existing);
      });
    }
  }
  for (const role of ['MEMBER', 'BRANCH'] as const) {
    test(`${type} ${role} elsewhere blocks OWNER`, async () => {
      const existing = seat(role, type);
      assert.deepEqual(await findBlockingMembership(fakeTx([existing]), 10, 2, 'OWNER'), existing);
    });
  }
  test(`${type} OWNER elsewhere allows OWNER`, async () => {
    assert.equal(await findBlockingMembership(fakeTx([seat('OWNER', type)]), 10, 2, 'OWNER'), null);
  });
  for (const existingRole of ['MEMBER', 'BRANCH', 'OWNER'] as const) {
    for (const newRole of ['MEMBER', 'BRANCH', 'OWNER'] as const) {
      test(`${type} same-agency ${existingRole} allows ${newRole}`, async () => {
        assert.equal(await findBlockingMembership(fakeTx([seat(existingRole, type)]), 10, 1, newRole), null);
      });
    }
  }
}

test('an allowed owner seat does not hide a blocking member seat', async () => {
  const blocking = seat('MEMBER', 'CHARGING', 3);
  assert.deepEqual(await findBlockingMembership(fakeTx([seat('OWNER', 'HOSTING'), blocking]), 10, 2, 'OWNER'), blocking);
});

test('same-agency membership does not hide another agency', async () => {
  const blocking = seat('BRANCH', 'CHARGING', 3);
  assert.deepEqual(await findBlockingMembership(fakeTx([seat('MEMBER', 'HOSTING', 2), blocking]), 10, 2, 'MEMBER'), blocking);
});

test('no seats or only another user seats allow joining', async () => {
  assert.equal(await findBlockingMembership(fakeTx([]), 10, 2, 'MEMBER'), null);
  assert.equal(await findBlockingMembership(fakeTx([seat('MEMBER', 'HOSTING')]), 20, 2, 'MEMBER'), null);
});

test('the conflict message matches the client wording exactly', () => {
  assert.equal(ALREADY_IN_AGENCY_MESSAGE, 'عذراً، هذا المستخدم موجود في وكالة بالفعل');
});
