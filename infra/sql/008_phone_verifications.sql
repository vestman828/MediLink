USE medilink;

CREATE TABLE IF NOT EXISTS phone_verifications (
  verification_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  phone VARCHAR(20) NOT NULL,
  purpose ENUM('signup', 'login', 'reset_password') NOT NULL DEFAULT 'signup',
  code_hash CHAR(64) NOT NULL,
  attempt_count INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  expires_at DATETIME NOT NULL,
  verified_at DATETIME NULL,
  verify_token VARCHAR(128) NULL,
  consumed_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_phone_purpose_created (phone, purpose, created_at),
  INDEX idx_verify_token (verify_token)
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
