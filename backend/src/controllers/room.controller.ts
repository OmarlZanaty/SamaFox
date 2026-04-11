import prisma from '../utils/prisma';
import { Request, Response } from 'express';
import { intParam } from '../utils/http';
import bcrypt from 'bcrypt';


export const getRooms = async (req: Request, res: Response) => {
  try {
    const { page = 1, limit = 20, type } = req.query;
    const skip = (Number(page) - 1) * Number(limit);

    const where = {
      isActive: true,
      ...(type && { type: String(type) })
    };

    const rooms = await prisma.room.findMany({
      where,
      include: {
        owner: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            level: true,
            vipLevel: true
          }
        },
        members: {
          take: 3,
          include: {
            user: {
              select: {
                id: true,
                name: true,
                avatarUrl: true,
                avatarFrameUrl: true, // ✅ ADD
              }
            }
          }
        },
        _count: {
          select: {
            members: true
          }
        }
      },
      skip,
      take: Number(limit),
      orderBy: {
        createdAt: 'desc'
      }
    });

    const total = await prisma.room.count({ where });

    res.json({
      rooms: rooms.map(room => ({
        id: room.id,
        name: room.name,
        description: room.description,
        coverImageUrl: room.coverImageUrl,
        backgroundImageUrl: room.backgroundImageUrl,
        type: room.type,
        maxSeats: room.maxSeats,
        owner: room.owner,
        membersCount: room._count.members,
members: room.members.map(m => ({
  userId: m.userId,
  role: m.role,
  isMuted: m.isMuted,
  joinedAt: m.joinedAt,
  user: m.user
})),

        createdAt: room.createdAt
      })),
      pagination: {
        page: Number(page),
        limit: Number(limit),
        total,
        totalPages: Math.ceil(total / Number(limit))
      }
    });
  } catch (error) {
    console.error('Get rooms error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getRoomById = async (req: Request, res: Response) => {
  try {
    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ error: 'Invalid roomId' });

    const room = await prisma.room.findUnique({
      where: { id: roomIdNum },
      include: {
        owner: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            displayId: true,
            level: true,
            vipLevel: true,
            activeFrameId: true,
            activeFrame: {
              select: {
                id: true,
                assetUrl: true,
                name: true,
              },
            },
          },
        },
        members: {
          include: {
            user: {
              select: {
                id: true,
                name: true,
                avatarUrl: true,
                displayId: true,
                relationId: true,
                activeFrameId: true,
                activeFrame: {
                  select: {
                    id: true,
                    assetUrl: true,
                    name: true,
                  },
                },
                level: true,
                vipLevel: true,
              },
            },
          },
        },
        _count: { select: { members: true } },
      },
    });

    if (!room) return res.status(404).json({ error: 'Room not found' });

    const relationIds = Array.from(
      new Set(room.members.map((m) => m.user.relationId).filter((id): id is number => !!id)),
    );
    const relations = relationIds.length
      ? await prisma.relation.findMany({
          where: { id: { in: relationIds } },
          include: {
            user1: { select: { id: true, name: true, avatarUrl: true } },
            user2: { select: { id: true, name: true, avatarUrl: true } },
          },
        })
      : [];
    const relationById = new Map(relations.map((r) => [r.id, r]));

    const seats = room.members.map((m, i) => ({
      seatNumber: i + 1,
      userId: m.userId,
      role: m.role,
      owner: {
        id: m.user.id,
        name: m.user.name,
        avatarUrl: m.user.avatarUrl,
        displayId: m.user.displayId,
        activeFrameId: m.user.activeFrameId,
        frameImageUrl: m.user.activeFrame?.assetUrl ?? null,
        relationPartner:
          m.user.relationId && relationById.get(m.user.relationId)
            ? relationById.get(m.user.relationId)!.user1Id === m.user.id
              ? relationById.get(m.user.relationId)!.user2
              : relationById.get(m.user.relationId)!.user1
            : null,
      },
    }));

    return res.json({
      id: room.id,
      name: room.name,
      description: room.description,
      coverImageUrl: room.coverImageUrl,
      backgroundImageUrl: room.backgroundImageUrl,
      type: room.type,
      maxSeats: room.maxSeats,
      owner: room.owner,
      ownerFrameImageUrl: room.owner.activeFrame?.assetUrl ?? null,
      membersCount: room._count.members,
      members: room.members.map(m => ({
        userId: m.userId,
        role: m.role,
        isMuted: m.isMuted,
        joinedAt: m.joinedAt,
        user: m.user,
      })),
      seats,
      createdAt: room.createdAt,
    });
  } catch (error) {
    console.error('Get room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export async function createRoom(req: Request, res: Response) {  try {
    const userId = req.userId;
    const {
      name,
      roomNumber,
      description,
      type,
      coverImage,
      coverImageUrl,
      backgroundImageUrl,
      password,
      // ❌ do NOT destructure maxSeats here to avoid redeclare
    } = req.body;

    // ✅ parse + clamp seats safely
    const rawMaxSeats = Number(req.body.maxSeats);
    const safeMaxSeats = Math.max(2, Math.min(30, Number.isFinite(rawMaxSeats) ? rawMaxSeats : 8));

    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    if (!name) {
      return res.status(400).json({ error: 'Room name is required' });
    }

    const passwordHash = password ? await bcrypt.hash(String(password), 10) : null;

    const room = await prisma.room.create({
      data: {
        name,
        description: description || null,
        type: type || 'public',
        maxSeats: safeMaxSeats, // ✅ USE safeMaxSeats (this is the important part)
        coverImageUrl: coverImage || coverImageUrl || null,
        backgroundImageUrl: backgroundImageUrl || null,

        passwordHash,

        ownerId: userId,
        isActive: true,
      },
      include: {
        owner: {
          select: {
            id: true,
            name: true,
            avatarUrl: true,
            level: true,
            vipLevel: true,
          },
        },
      },
    });

    await prisma.roomMember.create({
      data: {
        userId,
        roomId: room.id,
        role: 'owner',
        isMuted: false,
      },
    });

    return res.status(201).json({
      id: room.id,
      name: room.name,
      description: room.description,
      type: room.type,
      maxSeats: room.maxSeats,
      coverImageUrl: room.coverImageUrl,
      backgroundImageUrl: room.backgroundImageUrl,
      owner: room.owner,
      createdAt: room.createdAt,
    });
  } catch (error) {
    console.error('Create room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export const updateRoom = async (req: Request, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ error: 'Invalid roomId' });

    const { name, description, type, maxSeats, coverImageUrl, backgroundImageUrl } = req.body;

    const room = await prisma.room.findUnique({ where: { id: roomIdNum } });
    if (!room) return res.status(404).json({ error: 'Room not found' });
    if (room.ownerId !== userId) return res.status(403).json({ error: 'Only room owner can update the room' });

    const safeMaxSeats =
      maxSeats != null ? Math.max(2, Math.min(30, Number(maxSeats))) : undefined;

    const updatedRoom = await prisma.room.update({
      where: { id: roomIdNum },
      data: {
        ...(name && { name }),
        ...(description !== undefined && { description }),
        ...(type && { type }),
        ...(safeMaxSeats != null && Number.isFinite(safeMaxSeats) && { maxSeats: safeMaxSeats }),
        ...(coverImageUrl && { coverImageUrl }),
        ...(backgroundImageUrl && { backgroundImageUrl }),
      },
    });

    return res.json(updatedRoom);
  } catch (error) {
    console.error('Update room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export const deleteRoom = async (req: Request, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ error: 'Invalid roomId' });

    const room = await prisma.room.findUnique({ where: { id: roomIdNum } });
    if (!room) return res.status(404).json({ error: 'Room not found' });
    if (room.ownerId !== userId) return res.status(403).json({ error: 'Only room owner can delete the room' });

    await prisma.room.update({
      where: { id: roomIdNum },
      data: { isActive: false },
    });

    return res.json({ message: 'Room deleted successfully' });
  } catch (error) {
    console.error('Delete room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export const joinRoom = async (req: Request, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ error: 'Invalid roomId' });

    const room = await prisma.room.findUnique({
      where: { id: roomIdNum },
      include: { _count: { select: { members: true } } },
    });

    if (!room) return res.status(404).json({ error: 'Room not found' });
    if (!room.isActive) return res.status(400).json({ error: 'Room is not active' });

    const existing = await prisma.roomMember.findUnique({
      where: { userId_roomId: { userId, roomId: roomIdNum } },
    });

    if (existing) return res.status(409).json({ error: 'Already a member of this room' });

    const membership = await prisma.roomMember.create({
      data: { userId, roomId: roomIdNum, role: 'member', isMuted: false },
    });

    return res.status(201).json(membership);
  } catch (error) {
    console.error('Join room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};


export const leaveRoom = async (req: Request, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const roomIdNum = intParam(req.params.roomId);
    if (!roomIdNum) return res.status(400).json({ error: 'Invalid roomId' });

    await prisma.roomMember.delete({
      where: { userId_roomId: { userId, roomId: roomIdNum } },
    });

    return res.json({ message: 'Left room successfully' });
  } catch (error) {
    console.error('Leave room error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
};
