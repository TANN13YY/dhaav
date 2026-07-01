"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onRunDeleted = exports.onPendingTerritoryClaim = exports.onPendingRunCreated = exports.adminCreditRP = exports.setDeveloperRole = exports.claimWelcomeBonus = exports.onUserDeleted = exports.onUserCreated = void 0;
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
    // Create the initial user document
    await db.collection('Users').doc(uid).set({
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
        isAnonymous: false,
    });
});
// 2. onUserDeleted: Cleanup all user data
exports.onUserDeleted = functions.auth.user().onDelete(async (user) => {
    const uid = user.uid;
    // Note: For large collections, use a batch job. This is a simple cleanup for MVP.
    const batch = db.batch();
    // Delete user profile
    batch.delete(db.collection('Users').doc(uid));
    // Delete run history
    const runs = await db.collection('RunHistory').where('owner_id', '==', uid).get();
    runs.forEach(doc => batch.delete(doc.ref));
    // Delete territories
    const territories = await db.collection('PolygonTerritories').where('owner_id', '==', uid).get();
    territories.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
});
// 3. claimWelcomeBonus: Idempotent server-side claim
exports.claimWelcomeBonus = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
    }
    const uid = context.auth.uid;
    const userRef = db.collection('Users').doc(uid);
    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found');
        }
        const userData = userDoc.data();
        if ((userData === null || userData === void 0 ? void 0 : userData.welcomeRPClaimed) === true) {
            throw new functions.https.HttpsError('already-exists', 'Bonus already claimed');
        }
        transaction.update(userRef, {
            rpBalance: admin.firestore.FieldValue.increment(100),
            welcomeRPClaimed: true
        });
        // Add dummy run to history
        const runRef = db.collection('RunHistory').doc();
        transaction.set(runRef, {
            id: runRef.id,
            owner_id: uid,
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
    if (!context.auth || !context.auth.token.developer) {
        throw new functions.https.HttpsError('permission-denied', 'Must be a developer');
    }
    const { targetUid, amount } = data;
    if (!targetUid || typeof amount !== 'number' || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Invalid data format');
    }
    const userRef = db.collection('Users').doc(targetUid);
    await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists)
            return;
        transaction.update(userRef, {
            rpBalance: admin.firestore.FieldValue.increment(amount),
            totalRpEarned: admin.firestore.FieldValue.increment(amount)
        });
    });
    return { success: true };
});
// Helper to get week ID like "2026-W26"
function getWeekId() {
    const now = new Date();
    const jan4 = new Date(now.getFullYear(), 0, 4);
    const dayOfYear = Math.floor((now.getTime() - new Date(now.getFullYear(), 0, 1).getTime()) / 86400000) + 1;
    const weekNumber = Math.floor((dayOfYear - now.getDay() + jan4.getDay() + 6) / 7);
    return `${now.getFullYear()}-W${weekNumber.toString().padStart(2, '0')}`;
}
// 5. onPendingRunCreated: Triggered when app saves run offline/online
exports.onPendingRunCreated = functions.firestore.document('PendingRuns/{docId}').onCreate(async (snap, context) => {
    const data = snap.data();
    const uid = data.owner_id;
    if (!uid)
        return;
    const { pathCoordinates, totalDistanceKm, areaM2, isClosedLoop, totalDurationMs, isBusted } = data;
    if (typeof totalDistanceKm !== 'number')
        return;
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
    const userRef = db.collection('Users').doc(uid);
    const runRef = db.collection('RunHistory').doc(snap.id);
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
        // Save the run history
        transaction.set(runRef, {
            id: runRef.id,
            owner_id: uid,
            timestamp: data.timestamp || admin.firestore.FieldValue.serverTimestamp(),
            pathCoordinates: pathCoordinates || [],
            totalDistanceKm,
            totalDurationMs: totalDurationMs || 0,
            totalRP: calculatedRP,
            isBusted: !!isBusted,
            isClosedLoop: !!isClosedLoop,
            areaM2: areaM2 || 0,
            averagePaceMinPerKm: totalDistanceKm > 0 ? (totalDurationMs / 60000) / totalDistanceKm : 0
        });
        // Delete the pending run document
        transaction.delete(snap.ref);
    });
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
        if (typeof ed.rpStolen !== 'number' || ed.rpStolen <= 0 || !ed.enemyId) {
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
        // 1. Process all enemy deductions
        let actualStolenRP = 0;
        for (const ed of enemyDeductions) {
            const defenderRef = db.collection('Users').doc(ed.enemyId);
            const defenderDoc = await transaction.get(defenderRef);
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
                    transaction.set(defenderRef, dUpdates, { merge: true });
                }
            }
        }
        // 2. Adjust Attacker's balance: + actualStolenRP - selfOverlapRP
        if (attackerDoc.exists) {
            const aData = attackerDoc.data() || {};
            const aStoredWeekId = aData.currentWeekId || '';
            const netChange = actualStolenRP - selfOverlapRP;
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