const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const serviceAccount = require('./dhaav-app-firebase-adminsdk-h4gti-44e267d3e6.json');

initializeApp({
  credential: cert(serviceAccount)
});

const db = getFirestore();

async function fix() {
  const polys = await db.collection('PolygonTerritories').where('owner_id', '==', 'mock_user_alpha').get();
  let trueRP = 0;
  polys.forEach(doc => {
    trueRP += (doc.data().rp || 0);
  });
  
  await db.collection('Users').doc('mock_user_alpha').update({
    rpBalance: trueRP,
    totalRpEarned: trueRP,
    weeklyRpGained: trueRP,
    rpGained: trueRP,
  });
  console.log('Fixed to: ' + trueRP);
}

fix();
