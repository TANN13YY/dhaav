// migration.js
// Run from functions/: $env:GOOGLE_CLOUD_PROJECT="dhaav-app"; node migration.js

const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'dhaav-app',
  credential: admin.credential.applicationDefault(),
});
const db = admin.firestore();

async function migrate() {
  console.log('=== Starting Firestore Schema Migration ===');
  
  const usersSnap = await db.collection('Users').get();
  console.log(`Found ${usersSnap.size} user documents.`);
  
  let migratedUsers = 0;
  
  for (const doc of usersSnap.docs) {
    const data = doc.data();
    const currentId = doc.id;
    const dhaavId = data.dhaavId;
    
    // Check if the user document is already migrated
    // Or if it's the alpha mock user
    if (currentId === dhaavId || currentId === 'mock_user_alpha') {
      console.log(`User ${currentId} is already in correct format.`);
      continue;
    }
    
    if (!dhaavId) {
      console.log(`WARNING: User ${currentId} has no dhaavId! Skipping.`);
      continue;
    }
    
    console.log(`Migrating User: ${currentId} -> ${dhaavId}`);
    
    // 1. Create the new document
    const newData = { ...data, authUid: currentId };
    delete newData.isAnonymous; // Remove isAnonymous if it exists
    
    await db.collection('Users').doc(dhaavId).set(newData);
    
    // 2. Delete the old document
    await db.collection('Users').doc(currentId).delete();
    
    // 3. Migrate RunHistory
    const runsSnap = await db.collection('RunHistory').where('owner_id', '==', currentId).get();
    if (!runsSnap.empty) {
      const batch = db.batch();
      runsSnap.forEach(runDoc => {
        batch.update(runDoc.ref, { owner_id: dhaavId });
      });
      await batch.commit();
      console.log(`  - Migrated ${runsSnap.size} RunHistory documents.`);
    }
    
    // 4. Migrate PolygonTerritories
    const terrSnap = await db.collection('PolygonTerritories').where('owner_id', '==', currentId).get();
    if (!terrSnap.empty) {
      const batch = db.batch();
      terrSnap.forEach(terrDoc => {
        batch.update(terrDoc.ref, { owner_id: dhaavId });
      });
      await batch.commit();
      console.log(`  - Migrated ${terrSnap.size} PolygonTerritories.`);
    }
    
    migratedUsers++;
  }
  
  console.log(`\n=== Migration Complete. Migrated ${migratedUsers} users. ===`);
  process.exit(0);
}

migrate().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});
