import { randomInt } from 'node:crypto';

/** Server-drawn result for the game emojis (dice 1–6, slot 0–2); none for the rest. */
export function roomEmojiOutcome(emojiId: string): { result?: number } {
  if (emojiId === 'dice') return { result: randomInt(1, 7) };
  if (emojiId === 'slot') return { result: randomInt(0, 3) };
  return {};
}
