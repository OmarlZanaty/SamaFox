import { Request, Response } from 'express';
export declare const getRooms: (req: Request, res: Response) => Promise<void>;
export declare const getRoomById: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare function createRoom(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare const updateRoom: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const deleteRoom: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const joinRoom: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const leaveRoom: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=room.controller.d.ts.map