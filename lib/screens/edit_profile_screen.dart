import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;

  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _usernameCtrl;
  String _dob = 'Add a DOB';
  String _gender = 'Prefer not to say';
  String _dhaavId = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final uid = user?.uid;
    if (uid == null) {
      _setDefaultFields();
      setState(() => _isLoading = false);
      return;
    }
    try {
      final query = await FirebaseFirestore.instance.collection('Users').where('authUid', isEqualTo: uid).limit(1).get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();
        _dhaavId = doc.id;
        _firstNameCtrl = TextEditingController(text: data['firstName'] ?? '');
        _lastNameCtrl = TextEditingController(text: data['lastName'] ?? '');
        _usernameCtrl = TextEditingController(text: data['username'] ?? '');
        _dob = data['dob'] ?? 'Add a DOB';
        _gender = data['gender'] ?? 'Prefer not to say';
        
      } else {
        _setDefaultFields();
      }
    } catch (e) {
      debugPrint('Error loading profile data: $e');
      _setDefaultFields();
    }
    setState(() => _isLoading = false);
  }

  void _setDefaultFields() {
    final email = user?.email?.split('@').first ?? '';
    final parts = email.split('.');
    _firstNameCtrl = TextEditingController(text: parts.isNotEmpty ? parts[0].toUpperCase() : '');
    _lastNameCtrl = TextEditingController(text: parts.length > 1 ? parts[1].toUpperCase() : '');
    _usernameCtrl = TextEditingController(text: email.toUpperCase());
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: Theme.of(context).colorScheme.primary,
            surface: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dob = '${picked.day}/${picked.month}/${picked.year}');
    }
  }

  void _pickGender() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Male', 'Female', 'Non-binary', 'Prefer not to say']
              .map((g) => ListTile(
                    title: Text(g, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    trailing: _gender == g
                        ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      setState(() => _gender = g);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    HapticFeedback.lightImpact();
    
    // Sanitize and validate inputs
    String sanitizeText(String text, int maxLength) {
      String clean = text.trim();
      if (clean.length > maxLength) {
        clean = clean.substring(0, maxLength);
      }
      return clean;
    }

    final firstName = sanitizeText(_firstNameCtrl.text, 50);
    final lastName = sanitizeText(_lastNameCtrl.text, 50);
    
    // Username: Alphanumeric and underscores only
    String username = sanitizeText(_usernameCtrl.text, 30);
    username = username.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

    // Empty fields are allowed based on user request.

    setState(() => _isLoading = true);
    final uid = user?.uid;
    if (uid != null) {
      final query = await FirebaseFirestore.instance.collection('Users').where('authUid', isEqualTo: uid).limit(1).get();
      if (query.docs.isNotEmpty) {
        await query.docs.first.reference.set({
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'dob': _dob,
          'gender': _gender,
        }, SetOptions(merge: true));
      }
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
      );
    }
    
    // Compute initials
    String initials = 'U';
    final first = _firstNameCtrl.text.trim();
    final last = _lastNameCtrl.text.trim();
    if (first.isNotEmpty && last.isNotEmpty) {
      initials = '${first[0]}${last[0]}'.toUpperCase();
    } else if (first.isNotEmpty) {
      initials = first[0].toUpperCase();
    } else if (_usernameCtrl.text.trim().isNotEmpty) {
      final uname = _usernameCtrl.text.trim();
      initials = uname.substring(0, uname.length >= 2 ? 2 : 1).toUpperCase();
    } else {
      final name = user?.email?.split('@').first ?? 'U';
      initials = name.isNotEmpty ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase() : 'U';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('PROFILE', style: GoogleFonts.orbitron(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: Text('Done', style: GoogleFonts.inter(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile picture
            Center(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _firstNameCtrl,
                builder: (context, _, __) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _lastNameCtrl,
                    builder: (context, _, __) {
                      final f = _firstNameCtrl.text.trim();
                      final l = _lastNameCtrl.text.trim();
                      String liveInitials = initials;
                      if (f.isNotEmpty && l.isNotEmpty) {
                        liveInitials = '${f[0]}${l[0]}'.toUpperCase();
                      } else if (f.isNotEmpty) {
                        liveInitials = f[0].toUpperCase();
                      }
                      return CircleAvatar(
                        radius: 48,
                        backgroundColor: Theme.of(context).cardColor,
                        child: Text(
                          liveInitials,
                          style: GoogleFonts.orbitron(fontSize: 28, color: Theme.of(context).colorScheme.primary),
                        ),
                      );
                    }
                  );
                }
              ),
            ),
            if (_dhaavId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'DHAAV ID: $_dhaavId',
                style: GoogleFonts.orbitron(
                  color: Theme.of(context).hintColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
            SizedBox(height: 32),

            // Name fields
            Row(
              children: [
                Expanded(child: _buildField('First Name', _firstNameCtrl)),
                SizedBox(width: 16),
                Expanded(child: _buildField('Last Name', _lastNameCtrl)),
              ],
            ),
            SizedBox(height: 16),
            _buildField('Username', _usernameCtrl),
            SizedBox(height: 16),

            // DOB & Gender
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: _buildReadOnlyField('Date of Birth', _dob),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickGender,
                    child: _buildReadOnlyField('Gender', _gender),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 12)),
        SizedBox(height: 4),
        TextField(
          controller: ctrl,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: Theme.of(context).hintColor, fontSize: 11)),
          SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
        ],
      ),
    );
  }
}
