import { Request, Response } from 'express';
export declare const getMe: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const getUserById: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const updateProfile: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const updateGenderAndCountry: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const searchUsers: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const getUsersByCountry: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const followUser: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const unfollowUser: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const getFollowers: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
export declare const getFollowing: (req: Request, res: Response) => Promise<Response<any, Record<string, any>>>;
//# sourceMappingURL=user.controller.d.ts.map