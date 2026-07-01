const admin = require('firebase-admin');
const serviceAccount = require('../dhaav-app-firebase-adminsdk-h4gti-44e267d3e6.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function main() {
  // Get all users to map authUid -> dhaavId
  const usersSnap = await db.collection('Users').get();
  const authUidToDhaavId = {};
  usersSnap.forEach(doc => {
    const data = doc.data();
    if (data.authUid) {
      authUidToDhaavId[data.authUid] = doc.id;
    }
  });

  // Find all polygons
  const polySnap = await db.collection('PolygonTerritories').get();
  let updatedCount = 0;
  
  for (const doc of polySnap.docs) {
    const data = doc.data();
    const currentOwner = data.owner_id;
    
    // If the owner_id matches an authUid instead of a dhaavId
    if (authUidToDhaavId[currentOwner] && authUidToDhaavId[currentOwner] !== currentOwner) {
      const correctDhaavId = authUidToDhaavId[currentOwner];
      console.log(`Fixing territory ${doc.id}: ${currentOwner} -> ${correctDhaavId}`);
      await doc.ref.update({ owner_id: correctDhaavId });
      updatedCount++;
    }
  }

  console.log(`Fixed ${updatedCount} territories.`);
}

main().catch(console.error).then(() => process.exit(0));
