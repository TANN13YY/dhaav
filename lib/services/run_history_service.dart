import 'package:cloud_firestore/cloud_firestore.dart';
import 'run_tracker.dart';
import 'territory_service.dart';

class RunHistoryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Saves a run result to the database for the user.
  Future<void> saveRunResult(String userId, RunResult result) async {
    final docRef = _firestore.collection('RunHistory').doc();
    final data = result.toMap();
    data['owner_id'] = userId;
    data['id'] = docRef.id; // ensure ID matches doc
    
    await docRef.set(data);
  }

  /// Deletes a run result and deducts its RP from the user.
  Future<void> deleteRunResult(String userId, RunResult result) async {
    // Deduct the RP from the user's balance
    if (result.totalRP > 0) {
      await TerritoryService().creditRunRP(userId, -result.totalRP);
    }
    
    // Delete the run document
    await _firestore.collection('RunHistory').doc(result.id).delete();
  }

  /// Loads run history for the user from newest to oldest.
  Future<List<RunResult>> getUserRuns(String userId) async {
    final querySnapshot = await _firestore
        .collection('RunHistory')
        .where('owner_id', isEqualTo: userId)
        .get();

    final runs = querySnapshot.docs.map((doc) => RunResult.fromMap(doc.data(), doc.id)).toList();
    runs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return runs;
  }
}
