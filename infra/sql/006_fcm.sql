-- FCM 토큰 저장 컬럼 추가
ALTER TABLE users ADD COLUMN fcm_token VARCHAR(500) NULL;

-- 보호자 연동 요청 테이블 (승인 대기)
CREATE TABLE IF NOT EXISTS family_requests (
  request_id INT AUTO_INCREMENT PRIMARY KEY,
  guardian_id INT NOT NULL,
  patient_id INT NOT NULL,
  status ENUM('pending', 'accepted', 'rejected') NOT NULL DEFAULT 'pending',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (guardian_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (patient_id) REFERENCES users(user_id) ON DELETE CASCADE,
  UNIQUE KEY uq_request (guardian_id, patient_id)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
