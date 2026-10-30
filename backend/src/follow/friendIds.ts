/** Accepted requests union mutual accepted follows; never persist derived friendships. */
export async function friendIds(db: any, userId: number): Promise<number[]> {
  const [accepted, outgoing, incoming] = await Promise.all([
    db.friendship.findMany({ where: { status: 'accepted', OR: [{ userLowId: userId }, { userHighId: userId }] }, select: { userLowId: true, userHighId: true } }),
    db.follow.findMany({ where: { followerId: userId, status: 'ACCEPTED' }, select: { followingId: true } }),
    db.follow.findMany({ where: { followingId: userId, status: 'ACCEPTED' }, select: { followerId: true } }),
  ]);
  const followers = new Set<number>(incoming.map((r: any) => r.followerId));
  return [...new Set<number>([
    ...accepted.map((r: any) => r.userLowId === userId ? r.userHighId : r.userLowId),
    ...outgoing.filter((r: any) => followers.has(r.followingId)).map((r: any) => r.followingId),
  ])];
}
