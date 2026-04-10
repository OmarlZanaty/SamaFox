export const MAX_COINS_BALANCE = 2_147_483_647;

export function isValidPositiveAmount(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0;
}
