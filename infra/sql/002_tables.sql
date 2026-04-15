USE medilink;

CREATE TABLE IF NOT EXISTS users (
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL,
  phone VARCHAR(20) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role ENUM('patient', 'guardian', 'admin') NOT NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS family_map (
  map_id INT AUTO_INCREMENT PRIMARY KEY,
  guardian_id INT NOT NULL,
  patient_id INT NOT NULL,
  mapped_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_family_pair UNIQUE (guardian_id, patient_id),
  CONSTRAINT fk_family_guardian FOREIGN KEY (guardian_id) REFERENCES users(user_id),
  CONSTRAINT fk_family_patient FOREIGN KEY (patient_id) REFERENCES users(user_id)
);
