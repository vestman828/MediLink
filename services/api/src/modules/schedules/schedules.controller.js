const pool = require('../../config/db');
const { deleteUploadedImageByUrl } = require('../../utils/image-storage');

const RESERVED_FIXED_TIMES = new Set(['08:00:00', '12:00:00', '18:00:00', '22:00:00']);
const MAX_CUSTOM_TIMES_PER_DAY = 4;

function getKstDateString(base = new Date()) {
  return new Date(base.getTime() + 9 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
}

function normalizeScheduledTime(value) {
  const text = String(value ?? '').trim();
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(text);
  if (!match) return null;

  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = match[3] !== undefined ? Number(match[3]) : 0;
  if (
    !Number.isInteger(hour) ||
    !Number.isInteger(minute) ||
    !Number.isInteger(second) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59 ||
    second < 0 ||
    second > 59
  ) {
    return null;
  }

  const hh = String(hour).padStart(2, '0');
  const mm = String(minute).padStart(2, '0');
  const ss = String(second).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

function validateSchedules(schedules = []) {
  const keySet = new Set();
  const customCountByDay = new Map();

  for (const s of schedules) {
    if (
      s?.day_of_week === undefined ||
      s?.day_of_week === null ||
      typeof s?.time_slot !== 'string' ||
      typeof s?.scheduled_time !== 'string'
    ) {
      return '잘못된 스케줄 항목이 포함되어 있습니다.';
    }

    const normalizedTime = normalizeScheduledTime(s.scheduled_time);
    if (!normalizedTime) {
      return '복약 시간 형식이 올바르지 않습니다.';
    }
    s.scheduled_time = normalizedTime;

    const key = `${s.day_of_week}_${normalizedTime}`;
    if (keySet.has(key)) {
      return '같은 요일에서 복약 시간이 겹치도록 설정할 수 없습니다.';
    }
    keySet.add(key);

    if (s.time_slot === 'custom') {
      if (RESERVED_FIXED_TIMES.has(normalizedTime)) {
        return '직접 설정 시간은 아침/점심/저녁/취침 기본 시간과 겹칠 수 없습니다.';
      }

      const dayKey = Number(s.day_of_week);
      const nextCount = (customCountByDay.get(dayKey) ?? 0) + 1;
      if (nextCount > MAX_CUSTOM_TIMES_PER_DAY) {
        return '직접 설정 시간은 하루 최대 4개까지 설정할 수 있습니다.';
      }
      customCountByDay.set(dayKey, nextCount);
    }
  }

  return null;
}

async function ensureGuardianMappedPatient(guardianId, patientId) {
  const [mapping] = await pool.query(
    `SELECT map_id
     FROM family_map
     WHERE guardian_id = ? AND patient_id = ?
     LIMIT 1`,
    [guardianId, patientId]
  );
  return mapping.length > 0;
}

async function ensureUserCanAccessPatient(reqUser, patientId) {
  if (reqUser.role === 'patient') {
    return reqUser.user_id === Number(patientId);
  }
  if (reqUser.role === 'guardian') {
    return ensureGuardianMappedPatient(reqUser.user_id, Number(patientId));
  }
  return false;
}

async function ensureUserCanManagePatientMedicine(reqUser, patientMedicineId) {
  const [rows] = await pool.query(
    `SELECT pm.patient_id
     FROM patient_medicines pm
     WHERE pm.patient_medicine_id = ?
     LIMIT 1`,
    [patientMedicineId]
  );

  if (rows.length === 0) {
    return { ok: false, status: 404, message: '蹂듭슜???뺣낫瑜?李얠쓣 ???놁뒿?덈떎.' };
  }

  const patientId = Number(rows[0].patient_id);
  const canManage = await ensureUserCanAccessPatient(reqUser, patientId);
  if (!canManage) {
    return {
      ok: false,
      status: 403,
      message:
        reqUser.role === 'patient'
          ? '蹂몄씤 蹂듭빟 ?쒓컙留??ㅼ젙?????덉뒿?덈떎.'
          : '?곕룞???섏옄??蹂듭빟 ?쒓컙留??ㅼ젙?????덉뒿?덈떎.',
    };
  }

  return { ok: true, patientId };
}

async function createSchedule(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 시간을 설정할 수 있습니다.' });
    }

    const { patient_medicine_id, day_of_week, time_slot, scheduled_time } = req.body;
    if (
      patient_medicine_id === undefined ||
      day_of_week === undefined ||
      !time_slot ||
      !scheduled_time
    ) {
      return res.status(400).json({ success: false, message: '필수값이 누락되었습니다.' });
    }

    const normalizedTime = normalizeScheduledTime(scheduled_time);
    if (!normalizedTime) {
      return res
        .status(400)
        .json({ success: false, message: '복약 시간 형식이 올바르지 않습니다.' });
    }

    if (time_slot === 'custom' && RESERVED_FIXED_TIMES.has(normalizedTime)) {
      return res.status(400).json({
        success: false,
        message: '직접 설정 시간은 아침/점심/저녁/취침 기본 시간과 겹칠 수 없습니다.',
      });
    }

    const access = await ensureUserCanManagePatientMedicine(req.user, Number(patient_medicine_id));
    if (!access.ok) {
      return res.status(access.status).json({ success: false, message: access.message });
    }

    const [overlap] = await pool.query(
      `SELECT s.schedule_id
       FROM schedules s
       WHERE s.patient_medicine_id = ?
         AND s.day_of_week = ?
         AND s.scheduled_time = ?
       LIMIT 1`,
      [patient_medicine_id, day_of_week, normalizedTime]
    );

    if (overlap.length > 0) {
      return res
        .status(409)
        .json({ success: false, message: '같은 시간으로 중복 설정할 수 없습니다.' });
    }

    if (time_slot === 'custom') {
      const [customRows] = await pool.query(
        `SELECT COUNT(*) AS count
         FROM schedules
         WHERE patient_medicine_id = ?
           AND day_of_week = ?
           AND time_slot = 'custom'`,
        [patient_medicine_id, day_of_week]
      );
      const customCount = Number(customRows[0]?.count || 0);
      if (customCount >= MAX_CUSTOM_TIMES_PER_DAY) {
        return res.status(400).json({
          success: false,
          message: '직접 설정 시간은 하루 최대 4개까지 설정할 수 있습니다.',
        });
      }
    }

    const [result] = await pool.query(
      `INSERT INTO schedules (patient_medicine_id, day_of_week, time_slot, scheduled_time)
       VALUES (?, ?, ?, ?)`,
      [patient_medicine_id, day_of_week, time_slot, normalizedTime]
    );

    return res.status(201).json({ success: true, schedule_id: result.insertId });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

async function getTodaySchedules(req, res) {
  try {
    const patientId = Number(req.query.patient_id);
    if (!patientId) {
      return res
        .status(400)
        .json({ success: false, message: 'patient_id媛 ?꾩슂?⑸땲??' });
    }

    if (!['guardian', 'patient'].includes(req.user.role)) {
      return res
        .status(403)
        .json({ success: false, message: '蹂듭빟 ?뺣낫瑜?議고쉶??沅뚰븳???놁뒿?덈떎.' });
    }

    const canAccess = await ensureUserCanAccessPatient(req.user, patientId);
    if (!canAccess) {
      return res.status(403).json({
        success: false,
        message:
          req.user.role === 'patient'
            ? '蹂몄씤 蹂듭빟 ?뺣낫留?議고쉶?????덉뒿?덈떎.'
            : '?곕룞???섏옄 ?뺣낫留?議고쉶?????덉뒿?덈떎.',
      });
    }

    const targetDate = req.query.date || getKstDateString();

    const [rows] = await pool.query(
      `SELECT
         s.schedule_id,
         m.name AS medicine_name,
         m.unit,
         pm.dose,
         s.time_slot,
         s.scheduled_time,
         il.log_id,
         il.status,
         il.auth_method,
         il.photo_url,
         il.taken_at
       FROM schedules s
       JOIN patient_medicines pm ON s.patient_medicine_id = pm.patient_medicine_id
       JOIN medicines m ON pm.medicine_id = m.medicine_id
       LEFT JOIN intake_logs il
         ON il.schedule_id = s.schedule_id
         AND il.patient_id = pm.patient_id
         AND DATE(DATE_ADD(il.taken_at, INTERVAL 9 HOUR)) = ?
       WHERE pm.patient_id = ?
         AND pm.is_active = 1
         AND s.day_of_week = WEEKDAY(?)
       ORDER BY s.scheduled_time`,
      [targetDate, patientId, targetDate]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '?쒕쾭 ?ㅻ쪟' });
  }
}

async function getSchedulesByMedicine(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '蹂댄샇?먮쭔 蹂듭빟 ?ㅼ?以꾩쓣 議고쉶?????덉뒿?덈떎.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    if (!patientMedicineId) {
      return res.status(400).json({
        success: false,
        message: 'patient_medicine_id媛 ?꾩슂?⑸땲??',
      });
    }

    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    const [rows] = await pool.query(
      `SELECT schedule_id, day_of_week, time_slot, scheduled_time
       FROM schedules
       WHERE patient_medicine_id = ?
       ORDER BY day_of_week, scheduled_time`,
      [patientMedicineId]
    );

    return res.json({ success: true, data: rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '?쒕쾭 ?ㅻ쪟' });
  }
}

async function replaceSchedules(req, res) {
  try {
    if (req.user.role !== 'guardian') {
      return res
        .status(403)
        .json({ success: false, message: '보호자만 복약 시간을 수정할 수 있습니다.' });
    }

    const patientMedicineId = Number(req.params.patient_medicine_id);
    const { schedules, dose } = req.body;

    if (!Array.isArray(schedules)) {
      return res
        .status(400)
        .json({ success: false, message: 'schedules 배열이 필요합니다.' });
    }

    const invalidMessage = validateSchedules(schedules);
    if (invalidMessage) {
      return res.status(400).json({ success: false, message: invalidMessage });
    }

    const access = await ensureUserCanManagePatientMedicine(
      req.user,
      patientMedicineId
    );
    if (!access.ok) {
      return res
        .status(access.status)
        .json({ success: false, message: access.message });
    }

    const deletedPhotoUrls = [];
    const conn = await pool.getConnection();
    try {
      await conn.beginTransaction();

      // 복용량 업데이트 (dose만 바뀐 경우도 스케줄 기록은 건드리지 않음)
      if (dose) {
        await conn.query(
          `UPDATE patient_medicines SET dose = ? WHERE patient_medicine_id = ?`,
          [dose, patientMedicineId]
        );
      }

      // 기존 스케줄 조회
      const [existing] = await conn.query(
        `SELECT schedule_id, day_of_week, time_slot, scheduled_time
         FROM schedules
         WHERE patient_medicine_id = ?`,
        [patientMedicineId]
      );

      // 기존 스케줄을 key→schedule_id 맵으로 구성
      const existingMap = new Map();
      for (const s of existing) {
        const key = `${s.day_of_week}_${s.scheduled_time}_${s.time_slot}`;
        existingMap.set(key, s.schedule_id);
      }

      // 새 스케줄 key 집합
      const newKeySet = new Set();
      for (const s of schedules) {
        const key = `${s.day_of_week}_${s.scheduled_time}_${s.time_slot}`;
        newKeySet.add(key);
      }

      // 삭제할 스케줄: 기존에 있지만 새 목록에 없는 것
      const toDeleteIds = [];
      for (const [key, scheduleId] of existingMap) {
        if (!newKeySet.has(key)) {
          toDeleteIds.push(scheduleId);
        }
      }

      if (toDeleteIds.length > 0) {
        // 오늘 이후 복약 기록만 삭제 (과거 기록은 보존)
        const kstToday = getKstDateString();
        const [logsToDelete] = await conn.query(
          `SELECT photo_url
           FROM intake_logs
           WHERE schedule_id IN (?)
             AND DATE(DATE_ADD(taken_at, INTERVAL 9 HOUR)) >= ?
             AND photo_url IS NOT NULL`,
          [toDeleteIds, kstToday]
        );
        deletedPhotoUrls.push(...logsToDelete.map((log) => log.photo_url));

        await conn.query(
          `DELETE FROM intake_logs
           WHERE schedule_id IN (?)
             AND DATE(DATE_ADD(taken_at, INTERVAL 9 HOUR)) >= ?`,
          [toDeleteIds, kstToday]
        );
        await conn.query(
          `DELETE FROM schedules WHERE schedule_id IN (?)`,
          [toDeleteIds]
        );
      }

      // 추가할 스케줄: 새 목록에 있지만 기존에 없는 것
      for (const s of schedules) {
        const key = `${s.day_of_week}_${s.scheduled_time}_${s.time_slot}`;
        if (!existingMap.has(key)) {
          await conn.query(
            `INSERT INTO schedules (patient_medicine_id, day_of_week, time_slot, scheduled_time)
             VALUES (?, ?, ?, ?)`,
            [patientMedicineId, s.day_of_week, s.time_slot, s.scheduled_time]
          );
        }
        // 변경 없는 스케줄은 그대로 유지 (intake_logs 보존)
      }

      await conn.commit();
      await Promise.all(deletedPhotoUrls.map(deleteUploadedImageByUrl));
      return res.json({ success: true, message: '스케줄이 수정되었습니다.' });
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  } catch (err) {
    console.error(err);
    return res.status(500).json({ success: false, message: '서버 오류' });
  }
}

module.exports = {
  createSchedule,
  getTodaySchedules,
  getSchedulesByMedicine,
  replaceSchedules,
};
