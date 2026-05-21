CREATE TABLE IF NOT EXISTS guardian_alerts (
  alert_id INT AUTO_INCREMENT PRIMARY KEY,
  guardian_id INT NOT NULL,
  patient_id INT NOT NULL,
  patient_name VARCHAR(100) NOT NULL,
  time_slot VARCHAR(20) NOT NULL,
  alert_date DATE NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_alert (guardian_id, patient_id, time_slot, alert_date),
  CONSTRAINT fk_ga_guardian FOREIGN KEY (guardian_id) REFERENCES users(user_id),
  CONSTRAINT fk_ga_patient FOREIGN KEY (patient_id) REFERENCES users(user_id)
);
