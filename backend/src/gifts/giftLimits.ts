/** Shared by ordinary gift sends and CP invitations. */
export const MAX_QUANTITY = 7777;

export function isValidGiftQuantity(quantity: number): boolean {
  return Number.isInteger(quantity) && quantity >= 1 && quantity <= MAX_QUANTITY;
}
