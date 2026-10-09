import { Router } from 'express';
import { authenticate } from '../middlewares/auth.middleware';
import { requireAdminDashboard, requireSuperAdmin } from '../middlewares/adminDashboard.middleware';
import { staffController, staffResponses } from './staff.controller';
import { Operation } from './staff.service';

const router = Router();
const handle = (operation: Operation) => staffController(operation, true);
router.use(staffResponses);
router.use(authenticate, requireAdminDashboard);
router.get('/', handle('members'));
router.post('/managers', requireSuperAdmin, handle('appoint'));
router.get('/pool', handle('pool'));
router.put('/pool', requireSuperAdmin, handle('poolSet'));
router.get('/role-rewards', handle('roleRewards'));
router.put('/role-rewards', requireSuperAdmin, handle('roleRewardsSet'));
router.get('/audit', handle('audit'));
router.get('/grants', handle('grants'));
router.get('/bans', handle('bans'));
router.get('/ban-holders', handle('banHolders'));
// Fixed paths above, `/:roleId` ones below, so a word is never read as an id.
router.get('/:roleId', handle('member'));
router.post('/:roleId/extend', requireSuperAdmin, handle('extend'));
router.post('/:roleId/renew', requireSuperAdmin, handle('renew'));
router.post('/:roleId/revoke', requireSuperAdmin, handle('revoke'));
router.post('/:roleId/parent', requireSuperAdmin, handle('parent'));
export default router;
