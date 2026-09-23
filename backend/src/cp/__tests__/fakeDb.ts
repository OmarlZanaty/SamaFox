/**
 * A tiny in-memory stand-in for the Prisma client, covering only the calls
 * the CP / backgrounds services make. There is no database on the CI box
 * these run on, and the services take `db` as a parameter precisely so this
 * can be swapped in.
 *
 * Semantics that matter for the tests and are reproduced faithfully:
 *   • `updateMany` with `{ coinsBalance: { gte } }` guard — the atomic debit
 *   • `$transaction(fn)` rolls back every table when `fn` throws
 *   • unique (userId) on cp_unlocks / cp_unlock_grants, (userId,itemId) on user_items
 */

type Row = Record<string, any>;

const clone = <T>(v: T): T => (v === undefined ? v : JSON.parse(JSON.stringify(v)));

function matches(row: Row, where: Row | undefined): boolean {
  if (!where) return true;
  for (const [k, v] of Object.entries(where)) {
    if (k === 'OR') {
      if (!(v as Row[]).some((w) => matches(row, w))) return false;
      continue;
    }
    if (k === 'AND') {
      if (!(v as Row[]).every((w) => matches(row, w))) return false;
      continue;
    }
    if (k === 'NOT') {
      if (matches(row, v as Row)) return false;
      continue;
    }
    if (k === 'item') {
      // relation filter used by listUserBackgrounds: { item: { type } }
      const item = (row as any).__item;
      if (!item || !matches(item, v as Row)) return false;
      continue;
    }
    const cur = row[k];
    if (v !== null && typeof v === 'object' && !(v instanceof Date) && !Array.isArray(v)) {
      const cond = v as Row;
      if ('in' in cond && !cond.in.includes(cur)) return false;
      if ('gte' in cond && !(cur >= cond.gte)) return false;
      if ('gt' in cond && !(cur > cond.gt)) return false;
      if ('lt' in cond && !(cur < cond.lt)) return false;
      if ('startsWith' in cond && !String(cur).startsWith(cond.startsWith)) return false;
      if ('equals' in cond && cur !== cond.equals) return false;
      // compound unique { userAId_userBId: {...} } / { userId_itemId: {...} }
      if (k.includes('_') && !('in' in cond) && !('gte' in cond) && !('gt' in cond) && !('lt' in cond) && !('startsWith' in cond)) {
        for (const [ck, cv] of Object.entries(cond)) if (row[ck] !== cv) return false;
      }
      continue;
    }
    if (cur instanceof Date || v instanceof Date) {
      if (new Date(cur).getTime() !== new Date(v as any).getTime()) return false;
      continue;
    }
    if (cur !== v) return false;
  }
  return true;
}

function applyData(row: Row, data: Row) {
  for (const [k, v] of Object.entries(data)) {
    if (v && typeof v === 'object' && !(v instanceof Date) && !Array.isArray(v)) {
      if ('increment' in v) {
        row[k] = (row[k] ?? 0) + v.increment;
        continue;
      }
      if ('decrement' in v) {
        row[k] = (row[k] ?? 0) - v.decrement;
        continue;
      }
    }
    row[k] = v;
  }
  if ('updatedAt' in row) row.updatedAt = new Date();
}

function pick(row: Row, select?: Row): Row {
  if (!select) return clone(row);
  const out: Row = {};
  for (const [k, v] of Object.entries(select)) if (v) out[k] = clone(row[k]);
  return out;
}

export interface TableSpec {
  /** column(s) forming unique keys, e.g. [['userId'], ['userId','itemId']] */
  uniques?: string[][];
  idField?: string;
  idType?: 'int' | 'cuid';
}

export class FakeDb {
  tables: Record<string, Row[]> = {};
  specs: Record<string, TableSpec> = {};
  private seq: Record<string, number> = {};

  constructor(specs: Record<string, TableSpec>) {
    this.specs = specs;
    for (const name of Object.keys(specs)) {
      this.tables[name] = [];
      this.seq[name] = 1;
      (this as any)[name] = this.delegate(name);
    }
  }

  /** A table's rows, for assertions. Throws on an unknown table name. */
  rows(table: string): Row[] {
    const list = this.tables[table];
    if (!list) throw new Error(`FakeDb: unknown table "${table}"`);
    return list;
  }

  seed(table: string, rows: Row[]) {
    for (const r of rows) this.insert(table, { ...r });
  }

  private insert(table: string, data: Row): Row {
    const spec = this.specs[table]!;
    const idField = spec.idField ?? 'id';
    const row: Row = { ...data };
    if (row[idField] == null) {
      row[idField] = spec.idType === 'cuid' ? `${table}_${this.seq[table]!++}` : this.seq[table]!++;
    } else if (spec.idType !== 'cuid') {
      this.seq[table] = Math.max(this.seq[table]!, Number(row[idField]) + 1);
    }
    if (!('createdAt' in row)) row.createdAt = new Date();
    for (const u of spec.uniques ?? []) {
      const dup = this.tables[table]!.find((r) => u.every((c) => r[c] === row[c]));
      if (dup) {
        const err: any = new Error(`Unique constraint failed on ${u.join(',')}`);
        err.code = 'P2002';
        throw err;
      }
    }
    this.tables[table]!.push(row);
    return row;
  }

  private withRelations(table: string, row: Row, include?: Row): Row {
    if (!include) return clone(row);
    const out = clone(row);
    for (const [rel, sel] of Object.entries(include)) {
      if (!sel) continue;
      const selectObj = typeof sel === 'object' && (sel as any).select ? (sel as any).select : undefined;
      if (rel === 'userA' || rel === 'userB') {
        const u = this.tables.user!.find((x) => x.id === row[rel === 'userA' ? 'userAId' : 'userBId']);
        out[rel] = u ? pick(u, selectObj) : null;
      } else if (rel === 'user') {
        const u = this.tables.user!.find((x) => x.id === row.userId);
        out.user = u ? pick(u, selectObj) : null;
      } else if (rel === 'item') {
        const i = this.tables.item!.find((x) => x.id === row.itemId);
        out.item = i ? pick(i, selectObj) : null;
      } else if (rel === 'sender') {
        const u = this.tables.user!.find((x) => x.id === row.senderId);
        out.sender = u ? pick(u, selectObj) : null;
      }
    }
    return out;
  }

  private delegate(table: string) {
    const rows = () => this.tables[table]!;
    const decorate = (r: Row) => {
      // relation filters (userItem.item) need the joined row available
      if (table === 'userItem') (r as any).__item = this.tables.item?.find((i) => i.id === r.itemId);
      return r;
    };
    const find = (where?: Row) => rows().map(decorate).filter((r) => matches(r, where));
    const sortRows = (list: Row[], orderBy?: Row | Row[]) => {
      if (!orderBy) return list;
      const keys = Array.isArray(orderBy) ? orderBy : [orderBy];
      return [...list].sort((a, b) => {
        for (const k of keys) {
          const [f, dir] = Object.entries(k)[0] as [string, string];
          const av = a[f] instanceof Date ? a[f].getTime() : a[f];
          const bv = b[f] instanceof Date ? b[f].getTime() : b[f];
          if (av === bv) continue;
          const cmp = av > bv ? 1 : -1;
          return dir === 'desc' ? -cmp : cmp;
        }
        return 0;
      });
    };
    return {
      findUnique: async (args: Row) => {
        const r = find(args.where)[0];
        if (!r) return null;
        const withRel = this.withRelations(table, r, args.include);
        return args.select ? pick(withRel, args.select) : withRel;
      },
      findFirst: async (args: Row = {}) => {
        const r = sortRows(find(args.where), args.orderBy)[0];
        if (!r) return null;
        const withRel = this.withRelations(table, r, args.include);
        return args.select ? pick(withRel, args.select) : withRel;
      },
      findMany: async (args: Row = {}) => {
        let list = sortRows(find(args.where), args.orderBy);
        if (args.take) list = list.slice(0, args.take);
        return list.map((r) => {
          const withRel = this.withRelations(table, r, args.include);
          return args.select ? pick(withRel, args.select) : withRel;
        });
      },
      count: async (args: Row = {}) => find(args.where).length,
      create: async (args: Row) => clone(this.insert(table, { ...args.data })),
      createMany: async (args: Row) => {
        let count = 0;
        for (const d of args.data) {
          try {
            this.insert(table, { ...d });
            count++;
          } catch (e: any) {
            if (!(args.skipDuplicates && e.code === 'P2002')) throw e;
          }
        }
        return { count };
      },
      update: async (args: Row) => {
        const r = find(args.where)[0];
        if (!r) {
          const err: any = new Error('Record not found');
          err.code = 'P2025';
          throw err;
        }
        applyData(r, args.data);
        const withRel = this.withRelations(table, r, args.include);
        return args.select ? pick(withRel, args.select) : withRel;
      },
      updateMany: async (args: Row) => {
        const list = find(args.where);
        for (const r of list) applyData(r, args.data);
        return { count: list.length };
      },
      upsert: async (args: Row) => {
        const r = find(args.where)[0];
        if (r) {
          applyData(r, args.update);
          return clone(r);
        }
        return clone(this.insert(table, { ...args.create }));
      },
      delete: async (args: Row) => {
        const r = find(args.where)[0];
        if (!r) {
          const err: any = new Error('Record not found');
          err.code = 'P2025';
          throw err;
        }
        this.tables[table] = rows().filter((x) => x !== r);
        return clone(r);
      },
      deleteMany: async (args: Row = {}) => {
        const list = find(args.where);
        this.tables[table] = rows().filter((x) => !list.includes(x));
        return { count: list.length };
      },
      groupBy: async (args: Row) => {
        const by = args.by[0];
        const groups = new Map<any, number>();
        for (const r of find(args.where)) groups.set(r[by], (groups.get(r[by]) ?? 0) + 1);
        return [...groups.entries()].map(([k, n]) => ({ [by]: k, _count: { _all: n } }));
      },
    };
  }

  /** Interactive transaction with rollback-on-throw. */
  async $transaction(fn: (tx: any) => Promise<any>) {
    const snapshot = clone(this.tables);
    const seq = { ...this.seq };
    try {
      return await fn(this);
    } catch (e) {
      // Dates survive JSON only as strings — restore them.
      for (const [t, list] of Object.entries(snapshot)) {
        this.tables[t] = (list as Row[]).map((r) => {
          for (const k of Object.keys(r)) {
            if (/At$/.test(k) && typeof r[k] === 'string') r[k] = new Date(r[k]);
          }
          return r;
        });
      }
      this.seq = seq;
      throw e;
    }
  }
}

export function makeDb() {
  return new FakeDb({
    user: { uniques: [['id'], ['displayId']] },
    appSetting: { idField: 'key', idType: 'cuid', uniques: [['key']] },
    cpUnlock: { uniques: [['userId']] },
    cpUnlockGrant: { uniques: [['userId']] },
    cpUnlockGrantHistory: {},
    cpPair: { uniques: [['userAId', 'userBId']] },
    cpRequest: {},
    transaction: {},
    adminAuditLog: {},
    gift: { idType: 'cuid' },
    item: { idType: 'cuid' },
    userItem: { idType: 'cuid', uniques: [['userId', 'itemId']] },
  }) as FakeDb & Record<string, any>;
}
