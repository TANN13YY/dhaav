const admin = require('firebase-admin');
const fs = require('fs');

const serviceAccount = require('../dhaav-app-firebase-adminsdk-h4gti-44e267d3e6.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function main() {
  const territories = await db.collection('PolygonTerritories').get();
  console.log(`Found ${territories.docs.length} territories`);
  for (const doc of territories.docs) {
    const data = doc.data();
    console.log(`- Territory ${doc.id}: owner_id=${data.owner_id}, rp=${data.rp}`);
  }
}

main().catch(console.error).then(() => process.exit(0));
