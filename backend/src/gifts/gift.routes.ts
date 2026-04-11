import { Router } from 'express';
import { listGifts } from './gift.controller';

const router = Router();

router.get('/', listGifts);

export default router;
