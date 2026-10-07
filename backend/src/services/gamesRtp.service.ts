import prisma from '../utils/prisma';
import { cairoDay } from './halalGames.service';
import { getGameConfig } from './gameConfig.service';

/**
 * Coins staked vs coins paid out, per game per Cairo day, from game_ledger.
 * RTP is prizes / stakes (null on a day nobody played).
 */
export async function gamesRtp(daysWanted: number) {
  const span = Math.min(90, Math.max(1, Math.floor(daysWanted) || 14));
  const now = Date.now();
  const days = [...new Set(Array.from({ length: span }, (_, i) => cairoDay(new Date(now - (span - 1 - i) * 86_400_000))))];
  const rows = await prisma.gameLedger.groupBy({
    by: ['game', 'day', 'kind'],
    where: { day: { in: days } },
    _sum: { amount: true },
    _count: { _all: true },
  });
  const config = await getGameConfig();
  const games = new Map<string, Map<string, { stakes: number; prizes: number; rounds: number }>>();
  for (const row of rows) {
    const daily = games.get(row.game) ?? new Map<string, { stakes: number; prizes: number; rounds: number }>();
    games.set(row.game, daily);
    const cell = daily.get(row.day) ?? { stakes: 0, prizes: 0, rounds: 0 };
    daily.set(row.day, cell);
    const amount = Number(row._sum.amount ?? 0);
    if (row.kind === 'stake') { cell.stakes += amount; cell.rounds += row._count._all; }
    if (row.kind === 'prize') cell.prizes += amount;
  }
  const rtp = (prizes: number, stakes: number) => (stakes > 0 ? prizes / stakes : null);
  return {
    days,
    games: [...games.entries()].map(([game, daily]) => {
      const list = days.map((day) => {
        const cell = daily.get(day) ?? { stakes: 0, prizes: 0, rounds: 0 };
        return { day, ...cell, rtp: rtp(cell.prizes, cell.stakes) };
      });
      const stakes = list.reduce((s, d) => s + d.stakes, 0);
      const prizes = list.reduce((s, d) => s + d.prizes, 0);
      const target = config[game]?.rtpTargetBp;
      return {
        game, stakes, prizes, rounds: list.reduce((s, d) => s + d.rounds, 0), rtp: rtp(prizes, stakes),
        targetRtp: target == null ? 0.7 : target / 10_000, daily: list,
      };
    }).sort((a, b) => b.stakes - a.stakes),
  };
}
