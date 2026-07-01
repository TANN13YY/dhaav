import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  String? _dhaavId;

  String? get currentDhaavId => _dhaavId;

  Future<String?> fetchDhaavId(String authUid) async {
    if (_dhaavId != null) return _dhaavId;
    
    final query = await FirebaseFirestore.instance
        .collection('Users')
        .where('authUid', isEqualTo: authUid)
        .limit(1)
        .get();
        
    if (query.docs.isNotEmpty) {
      _dhaavId = query.docs.first.id;
      return _dhaavId;
    }
    return null;
  }
  
  void clear() {
    _dhaavId = null;
  }
}
