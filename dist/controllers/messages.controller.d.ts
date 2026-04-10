import { Request, Response } from 'express';
type AuthedRequest = Request & {
    userId?: number;
};
export declare function getConversations(req: AuthedRequest, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function getOrCreateConversation(req: AuthedRequest, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function getMessages(req: AuthedRequest, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function sendMessage(req: AuthedRequest, res: Response): Promise<Response<any, Record<string, any>>>;
export declare function markConversationRead(req: AuthedRequest, res: Response): Promise<Response<any, Record<string, any>>>;
export {};
//# sourceMappingURL=messages.controller.d.ts.map