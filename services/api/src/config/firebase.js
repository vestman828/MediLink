const admin = require('firebase-admin');
const path = require('path');

let initialized = false;

function getFirebaseAdmin() {
  if (!initialized) {
    const serviceAccount = require(path.join(__dirname, '../../firebase-adminsdk.json'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    initialized = true;
  }
  return admin;
}

// FCM 알림 전송 함수
async function sendFcmNotification(fcmToken, title, body, data = {}) {
  if (!fcmToken) return;
  try {
    const adminApp = getFirebaseAdmin();
    await adminApp.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: {
          channelId: 'medilink_channel',
          priority: 'high',
        },
      },
    });
    console.log(`[FCM] 알림 전송 성공: ${title}`);
  } catch (err) {
    console.error('[FCM] 알림 전송 실패:', err.message);
  }
}

module.exports = { getFirebaseAdmin, sendFcmNotification };
