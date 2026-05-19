const pool = require('../../config/db');

// 이행률 통계 (7일 / 30일)
async function getAdherence(req, res) {
  try {
    const { patient_id, period = 7 } = req.query;
    if (!patient_id) {
      return res.status(400).json({ success: false, message: 'patient_id가 필요합니다.' });
    }

    const days = Number(period);

    // 날짜별 복약 횟수 (KST = UTC+9 기준, DATE_FORMAT으로 문자열 반환)
    const [daily] = await pool.query(
      `SELECT
         DATE_FORMAT(DATE_ADD(il.taken_at, INTERVAL 9 HOUR), '%Y-%m-%d') AS date,
         COUNT(*) AS taken_count
       FROM intake_logs il
       WHERE il.patient_id = ?
         AND DATE_ADD(il.taken_at, INTERVAL 9 HOUR) >= DATE_SUB(
               DATE_ADD(NOW(), INTERVAL 9 HOUR), INTERVAL ? DAY)
       GROUP BY DATE_FORMAT(DATE_ADD(il.taken_at, INTERVAL 9 HOUR), '%Y-%m-%d')
       ORDER BY date ASC`,
      [patient_id, days]
    );

    // 포인트 합계 (7일)
    const [points7] = await pool.query(
      `SELECT COALESCE(SUM(points), 0) AS total_points
       FROM points_badges
       WHERE user_id = ?
         AND awarded_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)`,
      [patient_id]
    );

    // 포인트 전체 합계
    const [pointsAll] = await pool.query(
      `SELECT COALESCE(SUM(points), 0) AS total_points FROM points_badges WHERE user_id = ?`,
      [patient_id]
    );

    // 전체 복약 횟수
    const [totalTaken] = await pool.query(
      `SELECT COUNT(*) AS total FROM intake_logs WHERE patient_id = ?`,
      [patient_id]
    );

    const weeklyPoints = Number(points7[0]?.total_points || 0);
    const allPoints = Number(pointsAll[0]?.total_points || 0);
    const takenTotal = Number(totalTaken[0]?.total || 0);

    let grade = 'C';
    if (weeklyPoints >= 900) grade = 'S';
    else if (weeklyPoints >= 700) grade = 'A';
    else if (weeklyPoints >= 400) grade = 'B';

    // 배지 목록
    const badges = [];
    if (takenTotal >= 1)  badges.push({ type: 'first',    label: '첫 복약',    icon: '💊' });
    if (takenTotal >= 7)  badges.push({ type: 'week',     label: '7회 달성',   icon: '🌟' });
    if (takenTotal >= 30) badges.push({ type: 'month',    label: '30회 달성',  icon: '🏆' });
    if (weeklyPoints >= 700) badges.push({ type: 'diligent', label: '성실왕',   icon: '👑' });

    return res.json({
      success: true,
      data: {
        daily_adherence: daily,
        weekly_points: weeklyPoints,
        total_points: allPoints,
        total_taken: takenTotal,
        grade,
        badges,
      },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = { getAdherence };
