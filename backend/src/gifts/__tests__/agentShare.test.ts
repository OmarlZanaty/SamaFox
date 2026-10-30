// «نسبة الوكيل 20% تخص وكيل المضيفين فقط مفيش حد غيره ياخدها» — the agent share
// of a hosting agency may only land on the registered agent's OWNER seat.
import test from 'node:test';
import assert from 'node:assert/strict';
import { findAgencyCommissionOwner } from '../agencyCommission';

type Agency = { id: number; type: string; userId: number };
type Member = { id: number; agencyId: number; userId: number; role: string };

const fakeTx = (agencies: Agency[], members: Member[]) => ({
  chargingAgency: {
    findUnique: async ({ where }: any) => agencies.find((a) => a.id === where.id) ?? null,
  },
  agencyMember: {
    findFirst: async ({ where }: any) =>
      members.find(
        (m) => m.agencyId === where.agencyId && m.userId === where.userId && m.role === where.role,
      ) ?? null,
  },
});

const hosting: Agency = { id: 1, type: 'HOSTING', userId: 10 };
const owner: Member = { id: 100, agencyId: 1, userId: 10, role: 'OWNER' };
const branch: Member = { id: 101, agencyId: 1, userId: 20, role: 'BRANCH' };
const host: Member = { id: 102, agencyId: 1, userId: 30, role: 'MEMBER' };

test('the registered agent gets the share', async () => {
  const got = await findAgencyCommissionOwner(fakeTx([hosting], [owner, branch, host]), 1);
  assert.equal(got && got.userId, 10);
});

test('a فرع never gets the share, even when the agent has no OWNER row', async () => {
  assert.equal(await findAgencyCommissionOwner(fakeTx([hosting], [branch, host]), 1), null);
});

test('a stray second OWNER row is ignored', async () => {
  const stray: Member = { id: 103, agencyId: 1, userId: 20, role: 'OWNER' };
  const got = await findAgencyCommissionOwner(fakeTx([hosting], [stray, owner]), 1);
  assert.equal(got && got.userId, 10);
  assert.equal(await findAgencyCommissionOwner(fakeTx([hosting], [stray, branch]), 1), null);
});

test('a charging agency never pays the share', async () => {
  const charging: Agency = { id: 2, type: 'CHARGING', userId: 10 };
  const o: Member = { id: 200, agencyId: 2, userId: 10, role: 'OWNER' };
  assert.equal(await findAgencyCommissionOwner(fakeTx([charging], [o]), 2), null);
});
