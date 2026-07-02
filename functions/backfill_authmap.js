const admin = require('firebase-admin');

// Initialize with application default credentials
// Make sure to run this script from the functions directory
// Actually, since we're in the functions directory and it's deployed, let's use the local firebase-admin.
// Wait, if it's running locally against prod, we need GOOGLE_APPLICATION_CREDENTIALS or it might fail.
// Let's assume the user is logged into firebase CLI and we can just use `admin.initializeApp()`
// Let's use `firebase-admin` without credentials. If that fails, I can ask the user or figure it out.
// But we used functions/fix.js before using `admin.initializeApp({ projectId: 'dhaav-app' })` maybe?
// I will check how migration.js worked before it was deleted. I don't have it anymore.
// I will just use standard initialization.

admin.initializeApp({
  projectId: 'dhaav-app'
});

const db = admin.firestore();

async function backfillAuthMap() {
  console.log('Starting backfill for AuthMap...');
  const usersSnapshot = await db.collection('Users').get();
  
  if (usersSnapshot.empty) {
    console.log('No users found.');
    return;
  }

  const batch = db.batch();
  let count = 0;

  for (const doc of usersSnapshot.docs) {
    const data = doc.data();
    const authUid = data.authUid;
    const dhaavId = data.dhaavId;

    if (authUid && dhaavId) {
      console.log(`Mapping authUid: ${authUid} -> dhaavId: ${dhaavId}`);
      const mapRef = db.collection('AuthMap').doc(authUid);
      batch.set(mapRef, { dhaavId: dhaavId });
      count++;
    }
  }

  if (count > 0) {
    await batch.commit();
    console.log(`Successfully created ${count} AuthMap entries.`);
  } else {
    console.log('No mappings to create.');
  }
}

backfillAuthMap()
  .then(() => process.exit(0))
  .catch(err => {
    console.error(err);
    process.exit(1);
  });
