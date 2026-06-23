export function areFighterStatsVisible(
  fighter: { gym_id: string | null },
  gymId: string | null | undefined,
  isAdmin: boolean
): boolean {
  if (isAdmin) return true;
  if (!gymId) return false;
  return fighter.gym_id === gymId;
}
