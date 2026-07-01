const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'dhaav-app',
  credential: admin.credential.applicationDefault()
});

const db = admin.firestore();

async function fixWelcomeBonuses() {
  const usersSnap = await db.collection('Users').get();
  
  for (const userDoc of usersSnap.docs) {
    if (userDoc.id === 'mock_user_alpha') continue;
    
    console.log('Fixing user:', userDoc.id);
    
    // Get all welcome bonuses (distance = 0, RP = 100)
    const runsSnap = await db.collection('RunHistory')
      .where('owner_id', '==', userDoc.id)
      .where('totalDistanceKm', '==', 0)
      .where('totalRP', '==', 100)
      .get();
      
    if (runsSnap.size > 1) {
      console.log(`Found ${runsSnap.size} welcome bonuses. Deleting extras...`);
      // Keep the first one, delete the rest
      const docs = runsSnap.docs;
      const batch = db.batch();
      for (let i = 1; i < docs.length; i++) {
        batch.delete(docs[i].ref);
      }
      await batch.commit();
      console.log('Deleted extra welcome bonuses.');
      
      // Recalculate RP
      const allRunsSnap = await db.collection('RunHistory').where('owner_id', '==', userDoc.id).get();
      let totalRP = 0;
      allRunsSnap.forEach(runDoc => {
        // Exclude the ones we just deleted
        if (docs.slice(1).find(d => d.id === runDoc.id)) return;
        totalRP += (runDoc.data().totalRP || 0);
      });
      
      await userDoc.ref.update({
        rpBalance: totalRP,
        rpGained: totalRP,
        totalRpEarned: totalRP,
        weeklyRpGained: totalRP
      });
      console.log(`Updated RP to ${totalRP}`);
    } else {
      console.log('User has 1 or 0 welcome bonuses. No fix needed.');
    }
  }
}

fixWelcomeBonuses().catch(console.error);
