import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import os from 'os';
import path from 'path';

import { canActivateCp, canLevelUpCp, cpGiftRole, cpPointsFor } from '../cpGift.service';
import { DEFAULT_NAME_COLORS, isHexColor, nameColorSync, vipStyleSync, withNameStyle } from '../vipStyle.service';
import { isAnimatedFile } from '../animatedAvatar.service';
import { deviceFrom } from '../adminAudit.service';

describe('SPEC52 #34 — CP gift roles', () => {
  const ring = { coinCost: 1000, cpLevelPoints: null, cpActivate: true, cpLevelUp: false };
  const rose = { coinCost: 10, cpLevelPoints: 50, cpActivate: false, cpLevelUp: true };
  const both = { coinCost: 100, cpLevelPoints: null };

  test('roles map to the dashboard selector', () => {
    assert.equal(cpGiftRole(ring), 'activate');
    assert.equal(cpGiftRole(rose), 'level');
    assert.equal(cpGiftRole(both), 'both'); // legacy gifts keep doing both
  });

  test('activate-only adds no XP, level gifts use their XP value', () => {
    assert.equal(cpPointsFor(ring, 3), 0);
    assert.equal(cpPointsFor(rose, 3), 150);
    assert.equal(cpPointsFor(both, 2), 200); // null XP = the coin price
  });

  test('only activation gifts may create a relationship', () => {
    assert.equal(canActivateCp(ring), true);
    assert.equal(canActivateCp(rose), false);
    assert.equal(canLevelUpCp(ring), false);
    assert.equal(canActivateCp(both), true);
  });
});

describe('SPEC52 #7 — VIP name colours', () => {
  test('hex validation', () => {
    assert.ok(isHexColor('#FFD700'));
    assert.ok(isHexColor('#80FFD700'));
    assert.ok(!isHexColor('FFD700'));
    assert.ok(!isHexColor('#FFF'));
    assert.ok(!isHexColor('gold'));
  });

  test('defaults for VIP1–5, none without VIP, none when the VIP expired', () => {
    assert.equal(vipStyleSync(5).nameColor, DEFAULT_NAME_COLORS[5]);
    assert.equal(vipStyleSync(0).nameColor, null);
    assert.equal(nameColorSync(3, new Date(Date.now() - 1000)), null);
    const u = withNameStyle({ id: 1, vipLevel: 2 });
    assert.equal((u as any).nameColor, DEFAULT_NAME_COLORS[2]);
    const noVip = withNameStyle({ id: 2, name: 'x' } as any);
    assert.equal((noVip as any).nameColor, undefined);
  });
});

describe('SPEC52 #6 — the file decides whether it is animated', () => {
  const tmp = (name: string, bytes: Buffer) => {
    const p = path.join(os.tmpdir(), `spec52-${process.pid}-${name}`);
    fs.writeFileSync(p, bytes);
    return p;
  };

  test('a GIF renamed to .jpg is still animated', () => {
    const p = tmp('fake.jpg', Buffer.concat([Buffer.from('GIF89a', 'latin1'), Buffer.alloc(32)]));
    assert.equal(isAnimatedFile(p), true);
  });

  test('a plain PNG is not; an APNG (acTL before IDAT) is', () => {
    const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const png = tmp('a.png', Buffer.concat([sig, Buffer.from('....IHDR....IDAT', 'latin1')]));
    const apng = tmp('b.png', Buffer.concat([sig, Buffer.from('....IHDR....acTL....IDAT', 'latin1')]));
    assert.equal(isAnimatedFile(png), false);
    assert.equal(isAnimatedFile(apng), true);
  });

  test('animated WebP (ANIM chunk) is detected, a missing file is not', () => {
    const webp = tmp('c.webp', Buffer.from('RIFF\u0000\u0000\u0000\u0000WEBPVP8X\u0000\u0000\u0000\u0000ANIM', 'latin1'));
    assert.equal(isAnimatedFile(webp), true);
    assert.equal(isAnimatedFile(path.join(os.tmpdir(), 'does-not-exist-spec52')), false);
  });
});

describe('SPEC52 #43 — audit device label', () => {
  test('Android user agents give OS + model, browsers give the browser', () => {
    assert.equal(deviceFrom('Mozilla/5.0 (Linux; Android 14; SM-A266B) AppleWebKit'), 'Android 14 · SM-A266B');
    assert.equal(deviceFrom('Mozilla/5.0 (Windows NT 10.0) Chrome/130'), 'Chrome · Windows');
    assert.equal(deviceFrom(null, 'Realme C3'), 'Realme C3');
    assert.equal(deviceFrom(null), null);
  });
});
