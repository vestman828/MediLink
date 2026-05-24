USE medilink;

-- 일일 복약 메모 테이블 (컨디션, 부작용 기록)
CREATE TABLE IF NOT EXISTS daily_notes (
  note_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_id INT NOT NULL,
  note_date DATE NOT NULL,
  condition_score TINYINT NOT NULL DEFAULT 3 COMMENT '컨디션 1~5점',
  memo TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_patient_date (patient_id, note_date),
  CONSTRAINT fk_dn_patient FOREIGN KEY (patient_id) REFERENCES users(user_id)
);
