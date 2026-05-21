USE medilink;

CREATE TABLE IF NOT EXISTS medicines (
  medicine_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  unit VARCHAR(20) DEFAULT 'mg',
  description TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_medicines_name (name)
);

CREATE TABLE IF NOT EXISTS patient_medicines (
  patient_medicine_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_id INT NOT NULL,
  medicine_id INT NOT NULL,
  dose VARCHAR(50) NOT NULL,
  frequency VARCHAR(50),
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  start_date DATE NOT NULL,
  end_date DATE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pm_patient FOREIGN KEY (patient_id) REFERENCES users(user_id),
  CONSTRAINT fk_pm_medicine FOREIGN KEY (medicine_id) REFERENCES medicines(medicine_id)
);

CREATE TABLE IF NOT EXISTS schedules (
  schedule_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_medicine_id INT NOT NULL,
  day_of_week TINYINT NOT NULL,
  time_slot ENUM('morning', 'lunch', 'dinner', 'bedtime', 'custom') NOT NULL,
  scheduled_time TIME NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_sch_pm FOREIGN KEY (patient_medicine_id) REFERENCES patient_medicines(patient_medicine_id)
);

CREATE TABLE IF NOT EXISTS intake_logs (
  log_id INT AUTO_INCREMENT PRIMARY KEY,
  schedule_id INT NOT NULL,
  patient_id INT NOT NULL,
  status ENUM('taken', 'missed') NOT NULL DEFAULT 'taken',
  auth_method ENUM('button', 'photo') NOT NULL DEFAULT 'button',
  photo_url LONGTEXT,
  taken_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_il_schedule FOREIGN KEY (schedule_id) REFERENCES schedules(schedule_id),
  CONSTRAINT fk_il_patient FOREIGN KEY (patient_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS points_badges (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  points INT NOT NULL DEFAULT 0,
  reason VARCHAR(100),
  badge_type VARCHAR(50),
  awarded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pb_user FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS health_records (
  record_id INT AUTO_INCREMENT PRIMARY KEY,
  patient_id INT NOT NULL,
  meal_type ENUM('breakfast', 'lunch', 'dinner') NOT NULL,
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_hr_patient FOREIGN KEY (patient_id) REFERENCES users(user_id)
);

CREATE TABLE IF NOT EXISTS notification_logs (
  noti_id INT AUTO_INCREMENT PRIMARY KEY,
  guardian_id INT NOT NULL,
  patient_id INT NOT NULL,
  schedule_id INT NOT NULL,
  sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_nl_guardian FOREIGN KEY (guardian_id) REFERENCES users(user_id),
  CONSTRAINT fk_nl_patient FOREIGN KEY (patient_id) REFERENCES users(user_id),
  CONSTRAINT fk_nl_schedule FOREIGN KEY (schedule_id) REFERENCES schedules(schedule_id)
);
