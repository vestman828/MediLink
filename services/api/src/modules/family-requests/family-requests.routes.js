const express = require('express');
const auth = require('../../middleware/auth');
const { sendRequest, getPendingRequests, respondRequest } = require('./family-requests.controller');

const router = express.Router();

router.post('/send', auth, sendRequest);         // 보호자 → 요청 보내기
router.get('/pending', auth, getPendingRequests); // 환자 → 대기 중 요청 조회
router.post('/respond', auth, respondRequest);    // 환자 → 수락/거절

module.exports = router;
