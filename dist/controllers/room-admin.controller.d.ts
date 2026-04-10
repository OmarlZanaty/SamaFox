import { Request, Response } from 'express';
export declare function addRoomAdmin(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function removeRoomAdmin(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function muteUser(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function banUser(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function unbanUser(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function getBanList(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function toggleRoomLock(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function updateMaxSeats(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function setBackgroundMusic(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function updateRoomBackground(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function toggleSoundSettings(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function clearChat(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function getRoomAdmins(req: Request, res: Response): Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=room-admin.controller.d.ts.map