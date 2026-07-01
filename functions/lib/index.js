"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onRunDeleted = exports.onPendingTerritoryClaim = exports.submitRun = exports.adminSimulateTerritoryLoss = exports.adminClearMockData = exports.adminCreditRP = exports.setDeveloperRole = exports.claimWelcomeBonus = exports.onUserDeleted = exports.onUserCreated = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
// 1. onUserCreated: Initialize user profile with sequential ID and 0 RP
exports.onUserCreated = functions.auth.user().onCreate(async (user) => {
    const uid = user.uid;
    // Use a transaction to safely increment the global user counter
    const configRef = db.collection('System').doc('Config');
    const dhaavId = await db.runTransaction(async (transaction) => {
        var _a;
        const configDoc = await transaction.get(configRef);
        let nextId = 1;
        if (configDoc.exists) {
            nextId = (((_a = configDoc.data()) === null || _a === void 0 ? void 0 : _a.userCount) || 0) + 1;
        }
        transaction.set(configRef, { userCount: nextId }, { merge: true });
        // Format as 6-digit string: "000001"
        return nextId.toString().padStart(6, '0');
    });
    // Create the initial user document using dhaavId as the document ID
    await db.collection('Users').doc(dhaavId).set({
        authUid: uid,
        firstName: 'Runner',
        lastName: dhaavId,
        username: `user_${dhaavId}`,
        dhaavId: dhaavId,
        rpBalance: 0,
        rpGained: 0,
        rpLost: 0,
        weeklyRpGained: 0,
        weeklyRpLost: 0,
        totalRpEarned: 0,
        welcomeRPClaimed: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
});
// 2. onUserDeleted: Cleanup all user data
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
    const uid = user.uid;
    // Find the user's dhaavId by querying with authUid
    const userQuery = await db.collection('Users').where('authUid', '==', uid).limit(1).get();
    if (userQuery.empty)
        return;
    const userDoc = userQuery.docs[0];
    const dhaavId = userDoc.id;
    // Note: For large collections, use a batch job. This is a simple cleanup for MVP.
    const batch = db.batch();
    // Delete user profile
    batch.delete(userDoc.ref);
    // Delete run history
    const runs = await db.collection('RunHistory').where('owner_id', '==', dhaavId).get();
    runs.forEach(doc => batch.delete(doc.ref));
    // Delete territories
    const territories = await db.collection('PolygonTerritories').where('owner_id', '==', dhaavId).get();
    territories.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
});
// 3. claimWelcomeBonus: Idempotent server-side claim
exports.claimWelcomeBonus = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
    }
    const uid = context.auth.uid;
    const userQuery = await db.collection('Users').where('authUid', '==', uid).limit(1).get();
    if (userQuery.empty) {
        throw new functions.https.HttpsError('not-found', 'User not found');
    }
    const userRef = userQuery.docs[0].ref;
    const dhaavId = userQuery.docs[0].id;
    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const userData = userDoc.data();
        if ((userData === null || userData === void 0 ? void 0 : userData.welcomeRPClaimed) === true) {
            throw new functions.https.HttpsError('already-exists', 'Bonus already claimed');
        }
        const weekId = getWeekId();
        const storedWeekId = (userData === null || userData === void 0 ? void 0 : userData.currentWeekId) || '';
        const updates = {
            rpBalance: admin.firestore.FieldValue.increment(100),
            rpGained: admin.firestore.FieldValue.increment(100),
            totalRpEarned: admin.firestore.FieldValue.increment(100),
            welcomeRPClaimed: true
        };
        if (storedWeekId === weekId) {
            updates.weeklyRpGained = admin.firestore.FieldValue.increment(100);
        }
        else {
            updates.currentWeekId = weekId;
            updates.weeklyRpGained = 100;
            updates.weeklyRpLost = 0;
        }
        transaction.update(userRef, updates);
        // Add dummy run to RunHistory so the user sees it in their RP history
        const runRef = db.collection('RunHistory').doc();
        transaction.set(runRef, {
            id: runRef.id,
            owner_id: dhaavId,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            pathCoordinates: [],
            totalDistanceKm: 0,
            totalDurationMs: 0,
            totalRP: 100,
            averagePaceMinPerKm: 0,
            isBusted: false,
            isClosedLoop: false,
            areaM2: 0
        });
    });
    return { success: true };
});
// 4. setDeveloperRole: Assign Custom Claim
exports.setDeveloperRole = functions.https.onCall(async (data, context) => {
    // In production, this should be protected by a secret or existing admin check.
    // For this demo, we allow anyone who knows the secret code.
    if (data.secret !== 'super_secret_dhaav_admin_code') {
        throw new functions.https.HttpsError('permission-denied', 'Invalid secret');
    }
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
    }
    await admin.auth().setCustomUserClaims(context.auth.uid, { developer: true });
    return { success: true };
});
// 5. adminCreditRP: Developer mock data endpoint
exports.adminCreditRP = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('permission-denied', 'Must be authenticated');
    }
    const { targetUid, amount } = data;
    if (!targetUid || typeof amount !== 'number' || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid data format');
    }
    const userQuery = await db.collection('Users').where('authUid', '==', targetUid).limit(1).get();
    if (userQuery.empty) {
        throw new functions.https.HttpsError('not-found', 'User not found');
    }
    const userRef = userQuery.docs[0].ref;
    const dhaavId = userQuery.docs[0].id;
    const weekId = getWeekId();
    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const userData = userDoc.data() || {};
        const storedWeekId = userData.currentWeekId || '';
        const updates = {
            rpBalance: admin.firestore.FieldValue.increment(amount),
            rpGained: admin.firestore.FieldValue.increment(amount),
            totalRpEarned: admin.firestore.FieldValue.increment(amount)
        };
        if (storedWeekId === weekId) {
            updates.weeklyRpGained = admin.firestore.FieldValue.increment(amount);
        }
        else {
            updates.currentWeekId = weekId;
            updates.weeklyRpGained = amount;
            updates.weeklyRpLost = 0;
        }
        transaction.update(userRef, updates);
        // Add dummy run to RunHistory so the user sees it in their RP history
        const runRef = db.collection('RunHistory').doc();
        transaction.set(runRef, {
            id: runRef.id,
            owner_id: dhaavId,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            pathCoordinates: [],
            totalDistanceKm: 0,
            totalDurationMs: 0,
            totalRP: amount,
            averagePaceMinPerKm: 0,
            isBusted: false,
            isClosedLoop: false,
            areaM2: 0,
            isMock: true
        });
    });
    return { success: true };
});
// 6. adminClearMockData: Developer mock data endpoint
exports.adminClearMockData = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('permission-denied', 'Must be authenticated');
    }
    const weekId = getWeekId();
    const clearTimestamp = admin.firestore.FieldValue.serverTimestamp();
    // Step 0: Mark all real users with lastClearedAt BEFORE deleting runs.
    // This prevents the onRunDeleted trigger from decrementing rpBalance
    // when mock runs are deleted in the batch below.
    const usersSnap = await db.collection('Users').get();
    {
        const stampBatch = db.batch();
        for (const userDoc of usersSnap.docs) {
            stampBatch.update(userDoc.ref, { lastClearedAt: clearTimestamp });
        }
        await stampBatch.commit();
    }
    // Step 1: Delete ALL territories (user's mock territories go through
    // submitCustomTerritory and get a timestamp, so they look like real data).
    // Since no real runs exist yet in dev, wiping all territories is safe.
    const allTerrSnap = await db.collection('PolygonTerritories').get();
    {
        let batch = db.batch();
        let count = 0;
        for (const doc of allTerrSnap.docs) {
            batch.delete(doc.ref);
            count++;
            if (count >= 450) { // Firestore batch limit is 500
                await batch.commit();
                batch = db.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    // Step 2: Delete ALL battle history
    const allBattles = await db.collection('BattleHistory').get();
    {
        let batch = db.batch();
        let count = 0;
        for (const doc of allBattles.docs) {
            batch.delete(doc.ref);
            count++;
            if (count >= 450) {
                await batch.commit();
                batch = db.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    // Step 3: Delete ALL pending territory claims (so stale claims don't
    // fire after cleanup and mutate RP).
    const pendingSnap = await db.collection('PendingTerritoryClaims').get();
    {
        let batch = db.batch();
        let count = 0;
        for (const doc of pendingSnap.docs) {
            batch.delete(doc.ref);
            count++;
            if (count >= 450) {
                await batch.commit();
                batch = db.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    // Step 4: Delete mock runs (isMock or totalDistanceKm===0 except welcome bonus).
    // We already stamped lastClearedAt, so the onRunDeleted trigger will
    // skip these deletions.
    const allRunSnap = await db.collection('RunHistory').get();
    {
        let batch = db.batch();
        let count = 0;
        for (const doc of allRunSnap.docs) {
            const d = doc.data() || {};
            if (d.isMock === true || d.owner_id === 'mock_user_alpha') {
                batch.delete(doc.ref);
                count++;
            }
            else if (d.totalDistanceKm === 0 && d.totalRP !== 100) {
                batch.delete(doc.ref);
                count++;
            }
            if (count >= 450) {
                await batch.commit();
                batch = db.batch();
                count = 0;
            }
        }
        if (count > 0)
            await batch.commit();
    }
    // Step 5: Recalculate all user RP from remaining real runs.
    // Re-fetch users to get fresh data.
    const freshUsersSnap = await db.collection('Users').get();
    const userBatch = db.batch();
    for (const userDoc of freshUsersSnap.docs) {
        const isAlpha = userDoc.id === 'mock_user_alpha';
        let totalRP = 0;
        if (!isAlpha) {
            // Sum remaining real runs
            const runsSnap = await db.collection('RunHistory').where('owner_id', '==', userDoc.id).get();
            runsSnap.forEach(runDoc => {
                totalRP += (runDoc.data().totalRP || 0);
            });
        }
        else {
            // Sum Alpha's remaining territories
            const alphaTerritories = await db.collection('PolygonTerritories').where('owner_id', '==', 'mock_user_alpha').get();
            alphaTerritories.forEach(tDoc => {
                totalRP += (tDoc.data().rp || 0);
            });
        }
        userBatch.update(userDoc.ref, {
            rpBalance: totalRP,
            rpGained: totalRP,
            rpLost: 0,
            weeklyRpGained: totalRP,
            weeklyRpLost: 0,
            totalRpEarned: totalRP,
            currentWeekId: weekId
        });
    }
    await userBatch.commit();
    return { success: true };
});
// 7. adminSimulateTerritoryLoss: Developer mock data endpoint
exports.adminSimulateTerritoryLoss = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('permission-denied', 'Must be authenticated');
    }
    const { targetUid } = data;
    if (!targetUid) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing targetUid');
    }
    const userQuery = await db.collection('Users').where('authUid', '==', targetUid).limit(1).get();
    if (userQuery.empty) {
        return { success: false, message: 'User not found' };
    }
    const userRef = userQuery.docs[0].ref;
    const dhaavId = userQuery.docs[0].id;
    // Find a random territory owned by the user
    const query = await db.collection('PolygonTerritories')
        .where('owner_id', '==', dhaavId)
        .get();
    if (query.empty) {
        return { success: false, message: 'No territories to lose' };
    }
    const docs = query.docs;
    const randomDoc = docs[Math.floor(Math.random() * docs.length)];
    const territoryData = randomDoc.data();
    const rpToLose = territoryData.rp || 0;
    const alphaRef = db.collection('Users').doc('mock_user_alpha');
    const battleRef = db.collection('BattleHistory').doc();
    const weekId = getWeekId();
    await db.runTransaction(async (transaction) => {
        var _a;
        const userDoc = await transaction.get(userRef);
        const alphaDoc = await transaction.get(alphaRef);
        // 1. Give territory to enemy
        transaction.update(randomDoc.ref, { owner_id: 'mock_user_alpha' });
        // Log battle history
        transaction.set(battleRef, {
            attackerId: 'mock_user_alpha',
            defenderId: dhaavId,
            attackerName: 'Alpha Bot',
            defenderName: ((_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.username) || 'You',
            rpStolen: rpToLose,
            areaSqm: territoryData.area_sqm || 0.0,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            locationName: 'Simulated Battle',
            type: 'lost',
            participants: ['mock_user_alpha', dhaavId],
            capturedCoordinates: territoryData.coordinates || []
        });
        // 2. Deduct RP from user
        if (userDoc.exists) {
            const uData = userDoc.data() || {};
            const uStoredWeekId = uData.currentWeekId || '';
            const uUpdates = {
                rpBalance: admin.firestore.FieldValue.increment(-rpToLose),
                rpLost: admin.firestore.FieldValue.increment(rpToLose)
            };
            if (uStoredWeekId === weekId) {
                uUpdates.weeklyRpLost = admin.firestore.FieldValue.increment(rpToLose);
            }
            else {
                uUpdates.currentWeekId = weekId;
                uUpdates.weeklyRpGained = 0;
                uUpdates.weeklyRpLost = rpToLose;
            }
            transaction.update(userRef, uUpdates);
        }
        // 3. Give RP to enemy
        const alphaUpdates = {
            rpBalance: admin.firestore.FieldValue.increment(rpToLose),
            totalRpEarned: admin.firestore.FieldValue.increment(rpToLose),
            rpGained: admin.firestore.FieldValue.increment(rpToLose),
            username: 'Alpha Bot',
            firstName: 'Alpha',
            lastName: 'Bot',
            authUid: 'mock_user_alpha'
        };
        if (alphaDoc.exists) {
            const aData = alphaDoc.data() || {};
            const aStoredWeekId = aData.currentWeekId || '';
            if (aStoredWeekId === weekId) {
                alphaUpdates.weeklyRpGained = admin.firestore.FieldValue.increment(rpToLose);
            }
            else {
                alphaUpdates.currentWeekId = weekId;
                alphaUpdates.weeklyRpGained = rpToLose;
                alphaUpdates.weeklyRpLost = 0;
            }
        }
        else {
            alphaUpdates.currentWeekId = weekId;
            alphaUpdates.weeklyRpGained = rpToLose;
            alphaUpdates.weeklyRpLost = 0;
        }
        transaction.set(alphaRef, alphaUpdates, { merge: true });
    });
    return { success: true };
});
// Helper to get week ID like "2026-W26"
function getWeekId() {
    const now = new Date();
    const jan4 = new Date(now.getFullYear(), 0, 4);
    const dayOfYear = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 1).getTime()) / 86400000);
    const weekday = now.getDay() === 0 ? 7 : now.getDay();
    const jan4Weekday = jan4.getDay() === 0 ? 7 : jan4.getDay();
    const weekNumber = Math.floor((dayOfYear - weekday + jan4Weekday + 6) / 7);
    return `${now.getFullYear()}-W${weekNumber.toString().padStart(2, '0')}`;
}
// 5. submitRun: Triggered when app saves run offline/online
exports.submitRun = functions.https.onCall(async (data, context) => {
    var _a;
    const uid = (_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
    }
    const { pathCoordinates, totalDistanceKm, areaM2, isClosedLoop, totalDurationMs, isBusted } = data;
    if (typeof totalDistanceKm !== 'number') {
        throw new functions.https.HttpsError('invalid-argument', 'Missing distance');
    }
    // Server-side RP calculation
    let calculatedRP = 0;
    if (!isBusted) {
        const meters = totalDistanceKm * 1000;
        if (isClosedLoop) {
            calculatedRP = Math.round(meters / 100);
        }
        else {
            calculatedRP = Math.round(meters / 110);
        }
    }
    const userQuery = await db.collection('Users').where('authUid', '==', uid).limit(1).get();
    if (userQuery.empty) {
        throw new functions.https.HttpsError('not-found', 'User not found');
    }
    const userRef = userQuery.docs[0].ref;
    const dhaavId = userQuery.docs[0].id;
    const runRef = db.collection('RunHistory').doc();
    const weekId = getWeekId();
    await db.runTransaction(async (transaction) => {
        if (calculatedRP > 0) {
            const userDoc = await transaction.get(userRef);
            const userData = userDoc.data() || {};
            const storedWeekId = userData.currentWeekId || '';
            const updates = {
                rpBalance: admin.firestore.FieldValue.increment(calculatedRP),
                rpGained: admin.firestore.FieldValue.increment(calculatedRP),
            };
            if (storedWeekId === weekId) {
                updates.weeklyRpGained = admin.firestore.FieldValue.increment(calculatedRP);
            }
            else {
                updates.currentWeekId = weekId;
                updates.weeklyRpGained = calculatedRP;
                updates.weeklyRpLost = 0;
            }
            transaction.set(userRef, updates, { merge: true });
        }
        // Parse pathCoordinates to array of GeoPoints
        const parsedCoordinates = (pathCoordinates || []).map((c) => {
            if (Array.isArray(c) && c.length >= 2) {
                return new admin.firestore.GeoPoint(c[0], c[1]);
            }
            return c; // Might already be a GeoPoint
        });
        // Save the run history
        transaction.set(runRef, {
            id: runRef.id,
            owner_id: dhaavId,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            pathCoordinates: parsedCoordinates,
            totalDistanceKm,
            totalDurationMs: totalDurationMs || 0,
            totalRP: calculatedRP,
            isBusted: !!isBusted,
            isClosedLoop: !!isClosedLoop,
            areaM2: areaM2 || 0,
            averagePaceMinPerKm: totalDistanceKm > 0 ? (totalDurationMs / 60000) / totalDistanceKm : 0
        });
    });
    return { awardedRP: calculatedRP, success: true };
});
// 6. onPendingTerritoryClaim: Adjust balances for stolen territories
exports.onPendingTerritoryClaim = functions.firestore.document('PendingTerritoryClaims/{docId}').onCreate(async (snap, context) => {
    const data = snap.data();
    const uid = data.userId;
    if (!uid)
        return;
    const { enemyDeductions, selfOverlapRP, newDocRefId, rp, coordinates, area_sqm } = data;
    if (!Array.isArray(enemyDeductions) || typeof selfOverlapRP !== 'number')
        return;
    let totalStolen = 0;
    for (const ed of enemyDeductions) {
        if (typeof ed.rpStolen !== 'number' || ed.rpStolen < 0 || !ed.enemyId) {
            return; // Invalid deduction
        }
        totalStolen += ed.rpStolen;
    }
    if (totalStolen > 5000 || selfOverlapRP > 5000)
        return; // Hack attempt
    const attackerRef = db.collection('Users').doc(uid);
    const weekId = getWeekId();
    await db.runTransaction(async (transaction) => {
        const attackerDoc = await transaction.get(attackerRef);
        // 1. Process all enemy deductions - PRE-READ ALL DOCUMENTS
        const defenderDocs = [];
        for (const ed of enemyDeductions) {
            const defenderRef = db.collection('Users').doc(ed.enemyId);
            const doc = await transaction.get(defenderRef);
            defenderDocs.push({ doc, ed });
        }
        let actualStolenRP = 0;
        // 1.b Now do the writes for the defenders
        for (const item of defenderDocs) {
            const { doc: defenderDoc, ed } = item;
            if (defenderDoc.exists) {
                const dData = defenderDoc.data() || {};
                const dStoredWeekId = dData.currentWeekId || '';
                const currentBalance = dData.rpBalance || 0;
                const actualRpLost = Math.min(ed.rpStolen, currentBalance);
                if (actualRpLost > 0) {
                    actualStolenRP += actualRpLost;
                    const dUpdates = {
                        rpBalance: admin.firestore.FieldValue.increment(-actualRpLost),
                        rpLost: admin.firestore.FieldValue.increment(actualRpLost),
                    };
                    if (dStoredWeekId === weekId) {
                        dUpdates.weeklyRpLost = admin.firestore.FieldValue.increment(actualRpLost);
                    }
                    else {
                        dUpdates.currentWeekId = weekId;
                        dUpdates.weeklyRpGained = 0;
                        dUpdates.weeklyRpLost = actualRpLost;
                    }
                    transaction.set(defenderDoc.ref, dUpdates, { merge: true });
                }
            }
        }
        // 2. Adjust Attacker's balance: Real users already received their full RP from submitRun!
        // They only need to be penalized for self-overlap.
        if (attackerDoc.exists) {
            const aData = attackerDoc.data() || {};
            const aStoredWeekId = aData.currentWeekId || '';
            let netChange = -selfOverlapRP;
            // Alpha does not use submitRun, so we must manually grant Alpha the base RP + stolen RP
            if (uid === 'mock_user_alpha') {
                const baseRP = Math.max(0, (data.rp || 0) - totalStolen);
                netChange += baseRP + actualStolenRP;
            }
            if (netChange !== 0) {
                const aUpdates = {
                    rpBalance: admin.firestore.FieldValue.increment(netChange)
                };
                if (netChange > 0) {
                    aUpdates.rpGained = admin.firestore.FieldValue.increment(netChange);
                    if (aStoredWeekId === weekId) {
                        aUpdates.weeklyRpGained = admin.firestore.FieldValue.increment(netChange);
                    }
                    else {
                        aUpdates.currentWeekId = weekId;
                        aUpdates.weeklyRpGained = netChange;
                        aUpdates.weeklyRpLost = 0;
                    }
                }
                else if (netChange < 0) {
                    const loss = Math.abs(netChange);
                    aUpdates.rpLost = admin.firestore.FieldValue.increment(loss);
                    if (aStoredWeekId === weekId) {
                        aUpdates.weeklyRpLost = admin.firestore.FieldValue.increment(loss);
                    }
                    else {
                        aUpdates.currentWeekId = weekId;
                        aUpdates.weeklyRpGained = 0;
                        aUpdates.weeklyRpLost = loss;
                    }
                }
                transaction.set(attackerRef, aUpdates, { merge: true });
            }
        }
        // 3. Create the actual territory document now that RP is validated
        if (newDocRefId) {
            const territoryRef = db.collection('PolygonTerritories').doc(newDocRefId);
            transaction.set(territoryRef, {
                owner_id: uid,
                rp: rp,
                area_sqm: area_sqm || 0,
                coordinates: coordinates,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        }
        // 4. Delete the pending claim
        transaction.delete(snap.ref);
    });
});
// 7. onRunDeleted: Refund/Deduct RP when user deletes a run
exports.onRunDeleted = functions.firestore.document('RunHistory/{runId}').onDelete(async (snap, context) => {
    const data = snap.data();
    const uid = data.owner_id;
    const totalRP = data.totalRP || 0;
    if (!uid || totalRP <= 0)
        return;
    const userRef = db.collection('Users').doc(uid);
    const weekId = getWeekId();
    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists)
            return;
        const userData = userDoc.data() || {};
        // Ignore run deletion if it happened before the user was last cleared
        if (userData.lastClearedAt && data.timestamp) {
            if (data.timestamp.toMillis() <= userData.lastClearedAt.toMillis()) {
                return;
            }
        }
        const storedWeekId = userData.currentWeekId || '';
        const updates = {
            rpBalance: admin.firestore.FieldValue.increment(-totalRP),
            rpLost: admin.firestore.FieldValue.increment(totalRP)
        };
        if (storedWeekId === weekId) {
            updates.weeklyRpLost = admin.firestore.FieldValue.increment(totalRP);
        }
        else {
            updates.currentWeekId = weekId;
            updates.weeklyRpGained = 0;
            updates.weeklyRpLost = totalRP;
        }
        transaction.set(userRef, updates, { merge: true });
    });
});
//# sourceMappingURL=index.js.map