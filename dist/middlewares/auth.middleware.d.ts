import { RequestHandler } from 'express';
declare global {
    namespace Express {
        interface Request {
            userId?: number;
            authUser?: {
                id: number;
            };
        }
    }
}
export declare const authMiddleware: RequestHandler;
export declare const optionalAuth: RequestHandler;
export declare const authenticate: RequestHandler<import("express-serve-static-core").ParamsDictionary, any, any, import("qs").ParsedQs, Record<string, any>>;
export declare const requireAuth: RequestHandler<import("express-serve-static-core").ParamsDictionary, any, any, import("qs").ParsedQs, Record<string, any>>;
//# sourceMappingURL=auth.middleware.d.ts.map