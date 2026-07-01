const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'dhaav-app',
});
const db = admin.firestore();

async function fixAlpha() {
  console.log('Fixing Alpha Bot RP');
  
  // 1. Get Alpha Bot's true RP from territories
  const polys = await db.collection('PolygonTerritories').where('owner_id', '==', 'mock_user_alpha').get();
  
  let trueRP = 0;
  polys.forEach(doc => {
    trueRP += (doc.data().rp || 0);
  });
  
  console.log(`True RP of Alpha Bot: ${trueRP}`);
  
  // 2. Set Alpha Bot's fields
  const alphaDoc = await db.collection('Users').doc('mock_user_alpha').get();
  if (alphaDoc.exists) {
    const data = alphaDoc.data();
    console.log(`Current: totalRpEarned=${data.totalRpEarned}, weeklyRpGained=${data.weeklyRpGained}, rpBalance=${data.rpBalance}`);
    
    // We will just set all of them to trueRP to be perfectly consistent
    await alphaDoc.ref.update({
      rpBalance: trueRP,
      totalRpEarned: trueRP,
      weeklyRpGained: trueRP,
      rpGained: trueRP,
    });
    console.log('Fixed Alpha Bot!');
  } else {
    console.log('Alpha Bot not found.');
  }
}

fixAlpha().catch(console.error).then(() => process.exit(0));
