import test from 'node:test';
import assert from 'node:assert/strict';
import { roomEmojiOutcome } from '../roomEmojiOutcome';

test('dice lands on 1–6 and the slot on 0–2, covering every face', () => {
  const dice = new Set<number>();
  const slot = new Set<number>();
  for (let i = 0; i < 2000; i++) {
    dice.add(roomEmojiOutcome('dice').result!);
    slot.add(roomEmojiOutcome('slot').result!);
  }
  assert.deepEqual([...dice].sort(), [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...slot].sort(), [0, 1, 2]);
});

test('ordinary emojis carry no result', () => {
  for (const id of ['laugh', 'heart', 'crown']) assert.deepEqual(roomEmojiOutcome(id), {});
});
